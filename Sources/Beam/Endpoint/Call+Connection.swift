//
//  Call+Connection.swift
//  Beam
//
//  WebSocket orchestration: the handshake runs through the same attempt loop as an
//  HTTP call (interceptors, auth, 401 refresh, validation, retries, monitors), and
//  so does re-establishing a dropped connection. The connection loop lives here too:
//  `Socket` serves one connection at a time and says how it ended; this decides what
//  follows, decodes the messages and is the only one reporting the connection state.
//

import Foundation
import Synchronization

extension Call {
    typealias Messages<Message: Sendable> = ThrowingStream<Message, APIError<Failure>>
    typealias StateContinuation = AsyncStream<WebSocketConnectionState>.Continuation

    // MARK: - Connect

    func connect() async throws(APIError<Failure>) -> WebSocketConnection<Success, Failure> {
        let decoding = endpoint.responseBody
        let (stateStream, state) = AsyncStream<WebSocketConnectionState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        let first: URLSessionWebSocketTask
        do throws(APIError<Failure>) {
            first = try await openConnection(after: nil, state: state, accept: decoding.accept)
        } catch {
            state.yield(.disconnected(reason: .error(error.asVoid.kind)))
            state.finish()
            throw error
        }

        let socket = Socket(log: log, id: id, pingInterval: config.pingInterval, task: first)
        let (messages, events) = Messages<Success>.makeStream()
        let run = Task(name: "Beam.WebSocket.run") { [self] in
            await serve(from: first, on: socket, decoding: decoding, state: state, events: events)
        }
        let connection = WebSocketConnection(messages: messages, state: stateStream, json: config.json, log: log, id: id, socket: socket, run: run)
        // The consumer stopped iterating: close the socket (no-op if it already ended).
        events.onTermination {
            Task(name: "Beam.WebSocket.terminate") { await connection.close(.goingAway) }
        }
        return connection
    }

    // MARK: - Connection loop

    private func serve<Message: Sendable>(
        from first: URLSessionWebSocketTask,
        on socket: Socket,
        decoding: BodyDecoder<Message>,
        state: StateContinuation,
        events: Messages<Message>.Continuation
    ) async {
        let clock = ContinuousClock()
        let json = config.json
        let undecodable = Undecodable()
        var task = first

        while true {
            let openedAt = clock.now
            let ending = await socket.serve(task) { message in
                do throws(CodingError) {
                    events.yield(try Self.decode(message, with: decoding, json: json))
                    return true
                } catch {
                    undecodable.error.withLock { $0 = error }
                    return false
                }
            }

            let failure: APIError<Failure>
            switch ending {
            case .closed:
                return await finish(.closed, socket: socket, state: state, events: events)
            case .stopped:
                // A malformed message ends the connection with its decoding error, never retried.
                guard let error = undecodable.error.withLock({ $0 }) else {
                    return await finish(.intentional, socket: socket, state: state, events: events)
                }
                failure = .coding(error)
            case .dropped(let error):
                failure = APIError(error)
            }

            do throws(APIError<Failure>) {
                task = try await openConnection(after: (failure, clock.now - openedAt), state: state, accept: decoding.accept)
            } catch {
                // Cancelled: `disconnect()` was called or the consumer stopped iterating.
                return await finish(Task.isCancelled ? .intentional : .error(error.asVoid.kind), failure: Task.isCancelled ? nil : error, socket: socket, state: state, events: events)
            }
        }
    }

    private func finish<Message: Sendable>(
        _ reason: DisconnectionReason,
        failure: APIError<Failure>? = nil,
        socket: Socket,
        state: StateContinuation,
        events: Messages<Message>.Continuation
    ) async {
        await socket.end()
        state.yield(.disconnected(reason: reason))
        events.finish(throwing: failure)
        state.finish()
    }

    // MARK: - Opening

    /// When re-establishing, the dropped connection (`drop`) counts as the first attempt.
    func openConnection(
        after drop: (failure: APIError<Failure>, lifetime: Duration)?,
        state: StateContinuation,
        accept: ContentType?
    ) async throws(APIError<Failure>) -> URLSessionWebSocketTask {
        let progress = ConnectionProgress(state: state, maxAttempts: config.retry.maxAttempts)
        let previous = drop.map { drop in
            (error: drop.failure, attempt: EndpointContext.Attempt(status: HTTPStatus.switchingProtocols.rawValue, duration: drop.lifetime))
        }
        // Closed if the call fails after its upgrade.
        var opened: URLSessionWebSocketTask?

        do throws(APIError<Failure>) {
            return try await perform(.connection, accept: accept, after: previous, observers: [progress]) { request, _ throws(APIError<Failure>) in
                opened.map(Socket.abandon)
                let (task, response): (URLSessionWebSocketTask, HTTPURLResponse)
                do throws(WebSocketError) { (task, response) = try await Socket.handshake(request, session: session, log: log, id: id) } catch { throw APIError(error) }
                opened = task
                let upgraded = response.httpStatus.succeeds(for: .connection)
                return Response(http: response, body: upgraded ? .stream : .data(Data()))
            } output: { _ throws(APIError<Failure>) in
                guard let opened else { throw .connection(.unexpectedDisconnection) }
                return opened
            }
        } catch {
            opened.map(Socket.abandon)
            throw error
        }
    }

    // MARK: - Messages

    static func decode<Message>(_ message: URLSessionWebSocketTask.Message, with decoding: BodyDecoder<Message>, json: JSONCoding) throws(CodingError) -> Message {
        switch message {
        case .string(let text): try decoding.decode(Data(text.utf8), with: json)
        case .data(let data): try decoding.decode(data, with: json)
        @unknown default: throw .typeMismatch
        }
    }
}

private final class Undecodable: Sendable {
    let error = Mutex<CodingError?>(nil)
}

// MARK: - ConnectionProgress

struct ConnectionProgress: Monitor {
    let state: AsyncStream<WebSocketConnectionState>.Continuation
    let maxAttempts: Int

    func didSend(_ request: URLRequest, context: EndpointContext) {
        state.yield(.connecting)
    }

    func willRetry(after error: APIError<Void>, delay: Duration, context: EndpointContext) {
        state.yield(.reconnecting(attempt: context.attempt + 1, maxAttempts: maxAttempts))
    }

    func didSucceed(_ response: Response, context: EndpointContext) {
        state.yield(.connected)
    }
}

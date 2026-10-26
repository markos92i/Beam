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
    typealias StateContinuation = AsyncStream<WebSocketConnectionState>.Continuation

    // MARK: - Connect

    func connect<Outgoing>(socket socketConfig: SocketConfig) async throws(APIError<Failure>) -> WebSocketConnection<Success, Outgoing, Failure> {
        let decoding = endpoint.responseBody
        let (stateStream, state) = AsyncStream<WebSocketConnectionState>.makeStream(bufferingPolicy: .bufferingNewest(1))

        let first = try await openConnection(socket: socketConfig)
        state.yield(.connected)

        let socket = Socket(log: log, id: id, config: socketConfig, task: first.task)
        let (messages, events) = ThrowingStream<Success, APIError<Failure>>.makeStream()
        let run = Task(name: "Beam.WebSocket.run") { [self] in
            await serve(from: first.task, on: socket, config: socketConfig, decoding: decoding, state: state, events: events)
        }
        // The consumer stopped iterating, or released `messages`: close the socket. Capturing the
        // connection here would keep `messages` alive forever.
        events.onTermination {
            Task(name: "Beam.WebSocket.terminate") {
                await socket.close(code: .goingAway)
                run.cancel()
            }
        }
        return WebSocketConnection(
            messages: messages, state: stateStream, protocol: first.protocol,
            json: config.json, jsonFrames: socketConfig.jsonFrames, log: log, id: id, transport: .socket(socket, run: run)
        )
    }

    // MARK: - Connection loop

    private func serve<Message: Sendable>(
        from first: URLSessionWebSocketTask,
        on socket: Socket,
        config socketConfig: SocketConfig,
        decoding: BodyDecoder<Message>,
        state: StateContinuation,
        events: ThrowingStream<Message, APIError<Failure>>.Continuation
    ) async {
        let clock = ContinuousClock()
        let (json, log, id) = (config.json, log, id)
        let budget = RetryBudget()
        let progress = ConnectionProgress(state: state, budget: budget, maxAttempts: socketConfig.reconnect.maxAttempts)
        var task = first

        while true {
            let openedAt = clock.now
            let delivered = Atomic(false)
            let ending = await socket.serve(task) { message in
                do throws(CodingError) {
                    events.yield(try Self.decode(message, with: decoding, json: json))
                    delivered.store(true, ordering: .relaxed)
                } catch {
                    log.log(.codingFailed(id: id, what: "WebSocket message not decoded", detail: error.logDescription))
                }
            }

            let drop: WebSocketError
            switch ending {
            case .closed:
                return await finish(.closed, socket: socket, state: state, events: events)
            case .stopped:
                return await finish(.intentional, socket: socket, state: state, events: events)
            case .dropped(let error):
                drop = error
            }
            let failure = APIError<Failure>(drop)
            guard drop.reconnects(with: socketConfig) else {
                return await finish(.error(failure.asVoid.kind), failure: failure, socket: socket, state: state, events: events)
            }
            // A connection that delivered something, or held for a handshake's timeout, starts the budget over.
            if delivered.load(ordering: .relaxed) || clock.now - openedAt >= config.timeout { budget.reset() }

            do throws(APIError<Failure>) {
                task = try await openConnection(socket: socketConfig, after: (failure, clock.now - openedAt), budget: budget, progress: progress).task
            } catch {
                // Cancelled: `disconnect()` was called, or `messages` was released.
                let cancelled = Task.isCancelled
                return await finish(cancelled ? .intentional : .error(error.asVoid.kind), failure: cancelled ? nil : error, socket: socket, state: state, events: events)
            }
        }
    }

    private func finish<Message: Sendable>(
        _ reason: DisconnectionReason,
        failure: APIError<Failure>? = nil,
        socket: Socket,
        state: StateContinuation,
        events: ThrowingStream<Message, APIError<Failure>>.Continuation
    ) async {
        await socket.end()
        state.yield(.disconnected(reason: reason))
        events.finish(throwing: failure)
        state.finish()
    }

    // MARK: - Opening

    /// The first connection retries per `RequestConfig.retry`; a reconnection per
    /// `SocketConfig.reconnect`, with `drop` as its first failed attempt.
    func openConnection(
        socket socketConfig: SocketConfig,
        after drop: (failure: APIError<Failure>, lifetime: Duration)? = nil,
        budget: RetryBudget = RetryBudget(),
        progress: ConnectionProgress? = nil
    ) async throws(APIError<Failure>) -> (task: URLSessionWebSocketTask, protocol: String?) {
        let previous = drop.map { drop in
            (error: drop.failure, attempt: EndpointContext.Attempt(status: HTTPStatus.switchingProtocols.rawValue, duration: drop.lifetime))
        }
        // Closed if the call fails after its upgrade.
        var opened: (task: URLSessionWebSocketTask, protocol: String?)?

        do throws(APIError<Failure>) {
            return try await perform(
                .connection, after: previous, retry: drop == nil ? nil : socketConfig.reconnect,
                budget: budget, observers: progress.map { [$0] } ?? []
            ) { request, _ throws(APIError<Failure>) in
                opened.map { Socket.abandon($0.task) }
                let handshake: (task: URLSessionWebSocketTask, response: HTTPURLResponse, protocol: String?)
                do throws(WebSocketError) {
                    handshake = try await Socket.handshake(request, config: socketConfig, session: session, log: log, id: id)
                } catch {
                    throw APIError(error)
                }
                opened = (handshake.task, handshake.protocol)
                let upgraded = handshake.response.httpStatus.succeeds(for: .connection)
                return Response(http: handshake.response, body: upgraded ? .stream : .data(Data()))
            } output: { _ throws(APIError<Failure>) in
                guard let opened else { throw .connection(.unexpectedDisconnection) }
                return opened
            }
        } catch {
            opened.map { Socket.abandon($0.task) }
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

// MARK: - ConnectionProgress

/// Reports a reconnection's progress on the connection's `state`.
struct ConnectionProgress: Monitor {
    let state: AsyncStream<WebSocketConnectionState>.Continuation
    let budget: RetryBudget
    let maxAttempts: Int

    func willRetry(after error: APIError<Void>, delay: Duration, context: EndpointContext) {
        // A 401 repeats once to refresh credentials, outside the reconnection policy.
        guard error.status != .unauthorized else { return }
        state.yield(.reconnecting(attempt: budget.spent, maxAttempts: maxAttempts))
    }

    func didSucceed(_ response: Response, context: EndpointContext) {
        state.yield(.connected)
    }
}

//
//  Socket.swift
//  Beam
//
//  Actor that owns the full WebSocket lifecycle: connect, receive, send,
//  ping keepalive, reconnect, and disconnect. One Socket per connection.
//

import Foundation

actor Socket<Success: Sendable, Failure: Sendable> {

    private let session: any SessionProtocol
    private let mapper: any MapperProtocol
    private let config: RequestConfig
    private let log: BeamLogger
    private let id: String
    private let requestBuilder: @Sendable () async throws -> URLRequest
    private let stateContinuation: AsyncStream<WebSocketConnectionState>.Continuation?

    private var intentionalDisconnect = false
    private var activeTask: URLSessionWebSocketTask?

    init(
        session: any SessionProtocol,
        mapper: any MapperProtocol,
        config: RequestConfig,
        log: BeamLogger,
        id: String,
        requestBuilder: @escaping @Sendable () async throws -> URLRequest,
        stateContinuation: AsyncStream<WebSocketConnectionState>.Continuation? = nil
    ) {
        self.session = session
        self.mapper = mapper
        self.config = config
        self.log = log
        self.id = id
        self.requestBuilder = requestBuilder
        self.stateContinuation = stateContinuation
    }

    // MARK: - Active Connection

    private var activeConnection: URLSessionWebSocketTask {
        get throws(APIError<Failure>) {
            guard let task = activeTask, task.state == .running else {
                throw .connectionClosed(code: 1006, reason: nil)
            }
            return task
        }
    }

    // MARK: - Open

    /// Opens the WebSocket connection and returns the message stream.
    /// Waits for the first connection to be established before returning.
    func open() async throws(APIError<Failure>) -> AsyncThrowingStream<StreamEvent<Success, Failure>, Error> {
        let (stream, continuation) = AsyncThrowingStream<StreamEvent<Success, Failure>, Error>.makeStream()

        continuation.onTermination = { @Sendable [weak self] _ in
            guard let self else { return }
            Task { await self.markDisconnected() }
        }

        stateContinuation?.yield(.connecting)

        let connectionResult: Result<Void, APIError<Failure>> = await withCheckedContinuation { openContinuation in
            Task.detached { [self] in
                await self.run(continuation: continuation, openContinuation: openContinuation)
            }
        }

        switch connectionResult {
        case .success:
            return stream
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Send

    /// Sends a typed value as a JSON-encoded binary message.
    func send(_ value: Success) async throws(APIError<Failure>) {
        let task = try activeConnection

        let data: Data
        do {
            guard let encodable = value as? any Encodable else {
                throw MapperError.unsuported
            }
            data = try mapper.encode(encodable)
        } catch let error as MapperError {
            throw APIError<Failure>(from: error)
        } catch {
            throw APIError<Failure>.encode
        }

        do {
            try await task.send(.data(data))
            log.log(.wsSend(id: id, type: "binary", body: .data(data)))
        } catch {
            throw APIError<Failure>(from: WebSocketError.sendFailed(error))
        }
    }

    /// Sends raw data as a binary message.
    func send(data: Data) async throws(APIError<Failure>) {
        let task = try activeConnection

        do {
            try await task.send(.data(data))
            log.log(.wsSend(id: id, type: "binary", body: .data(data)))
        } catch {
            throw APIError<Failure>(from: WebSocketError.sendFailed(error))
        }
    }

    /// Sends a string as a text message.
    func send(text: String) async throws(APIError<Failure>) {
        let task = try activeConnection

        do {
            try await task.send(.string(text))
            log.log(.wsSend(id: id, type: "text", body: .data(text.data(using: .utf8) ?? Data())))
        } catch {
            throw APIError<Failure>(from: WebSocketError.sendFailed(error))
        }
    }

    // MARK: - Disconnect

    /// Gracefully disconnects the WebSocket.
    func disconnect(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) {
        intentionalDisconnect = true
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) }
        log.log(.wsClose(id: id, code: code.rawValue, reason: reasonStr))
        activeTask?.cancel(with: code, reason: reason)
        activeTask = nil
    }

    // MARK: - Main Loop

    private func run(
        continuation: AsyncThrowingStream<StreamEvent<Success, Failure>, Error>.Continuation,
        openContinuation: CheckedContinuation<Result<Void, APIError<Failure>>, Never>? = nil
    ) async {
        let retryPolicy = config.retry
        var attempt = 0
        var pendingOpenContinuation = openContinuation

        while !intentionalDisconnect {
            // 1. Connect
            let request: URLRequest
            do {
                request = try await requestBuilder()
            } catch {
                let apiError = APIError<Failure>(error: error)
                if let openCont = pendingOpenContinuation {
                    pendingOpenContinuation = nil
                    openCont.resume(returning: .failure(apiError))
                } else {
                    finish(continuation: continuation, error: apiError)
                }
                return
            }

            let wsTask = session.webSocketTask(with: request)
            wsTask.resume()
            self.activeTask = wsTask
            log.log(.wsOpen(id: id, url: request.url!, headers: request.allHTTPHeaderFields))

            // 2. Connected
            stateContinuation?.yield(.connected)
            if let openCont = pendingOpenContinuation {
                pendingOpenContinuation = nil
                openCont.resume(returning: .success(()))
            }
            if attempt > 0 {
                continuation.yield(.reconnected)
                attempt = 0
            }

            // 3. Start ping if configured
            let pingTask = startPingIfNeeded(wsTask: wsTask)

            // 4. Consume messages until stream ends
            let disconnectError = await consumeMessages(from: wsTask, continuation: continuation)
            pingTask?.cancel()
            self.activeTask = nil

            guard !intentionalDisconnect else { break }

            // 5. Decide: reconnect or finish
            guard let error = disconnectError, isReconnectable(error), retryPolicy.maxAttempts > 0 else {
                finish(continuation: continuation, error: disconnectError.map { APIError(error: $0) })
                return
            }

            // 6. Start reconnection
            attempt = 1
            stateContinuation?.yield(.reconnecting(attempt: attempt, maxAttempts: retryPolicy.maxAttempts))
            continuation.yield(.reconnecting(attempt: attempt, maxAttempts: retryPolicy.maxAttempts))

            let delay = retryPolicy.delay(for: attempt)
            if delay > 0 {
                log.log(.wsReconnect(id: String(id.prefix(4)), attempt: attempt, max: retryPolicy.maxAttempts, delay: delay))
                try? await Task.sleep(for: .seconds(delay))
            }

            stateContinuation?.yield(.connecting)
        }

        // Clean exit (intentional disconnect)
        stateContinuation?.yield(.disconnected(reason: .intentional))
        continuation.finish()
        stateContinuation?.finish()
    }

    // MARK: - Message Consumption

    private func consumeMessages(
        from wsTask: URLSessionWebSocketTask,
        continuation: AsyncThrowingStream<StreamEvent<Success, Failure>, Error>.Continuation
    ) async -> (any Error)? {
        let mapper = self.mapper

        do {
            while wsTask.state == .running && !intentionalDisconnect {
                let message = try await wsTask.receive()
                let (type, body): (String, LogEvent.Body) = switch message {
                case .string(let text): ("text", .data(text.data(using: .utf8) ?? Data()))
                case .data(let data): ("binary", .data(data))
                @unknown default: ("unknown", .none)
                }
                log.log(.wsReceive(id: id, type: type, body: body))
                let decoded: Success = try deserialize(message: message, mapper: mapper)
                continuation.yield(.message(decoded))
            }
            return nil
        } catch {
            return WebSocketError.from(error)
        }
    }

    // MARK: - Ping

    private func startPingIfNeeded(wsTask: URLSessionWebSocketTask) -> Task<Void, Never>? {
        guard let interval = config.pingInterval, interval >= 1, interval <= 300 else { return nil }
        let log = self.log
        let id = self.id

        return Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                guard await self?.intentionalDisconnect != true else { break }

                do {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        wsTask.sendPing { error in
                            if let error { cont.resume(throwing: error) }
                            else { cont.resume() }
                        }
                    }
                    log.log(.wsPing(id: id))
                } catch {
                    // Ping failed — force disconnect to break message loop
                    wsTask.cancel(with: .abnormalClosure, reason: nil)
                    break
                }
            }
        }
    }

    // MARK: - Helpers

    private func markDisconnected() {
        intentionalDisconnect = true
    }

    private func finish(
        continuation: AsyncThrowingStream<StreamEvent<Success, Failure>, Error>.Continuation,
        error: APIError<Failure>?
    ) {
        if let error {
            log.log(.error(id: id, icon: error.icon, name: error.name, detail: error.detail, attempt: 0))
            stateContinuation?.yield(.disconnected(reason: .error("\(error)")))
            continuation.finish(throwing: error)
        } else {
            stateContinuation?.yield(.disconnected(reason: .closed))
            continuation.finish()
        }
        stateContinuation?.finish()
    }

    private func isReconnectable(_ error: any Error) -> Bool {
        switch error {
        case let wsError as WebSocketError:
            wsError.isReconnectable
        case let urlError as URLError:
            [.networkConnectionLost, .timedOut, .notConnectedToInternet].contains(urlError.code)
        default:
            false
        }
    }

    private func deserialize(message: URLSessionWebSocketTask.Message, mapper: any MapperProtocol) throws -> Success {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else { throw MapperError.incorrect }
            return try mapper.decode(data: data)
        case .data(let data):
            return try mapper.decode(data: data)
        @unknown default:
            throw MapperError.unsuported
        }
    }
}

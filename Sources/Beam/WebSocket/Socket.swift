//
//  Socket.swift
//  Beam
//
//  The WebSocket transport: handshake, receive, send, ping keep-alive and close.
//  Like `Client` for HTTP, it doesn't decide anything and speaks its own error
//  (`WebSocketError`): it hands raw messages up and says how a connection ended.
//  `Endpoint` decodes the messages, decides whether a dropped connection is
//  re-established, and reports the connection's state.
//

import Foundation

actor Socket {
    private let log: BeamLogger
    private let id: String
    private let pingInterval: Duration?

    private var task: URLSessionWebSocketTask?

    private var isClosed = false

    enum Ending: Sendable {
        /// Server closed with 1000 or 1001.
        case closed
        case dropped(WebSocketError)
        /// `close`, the consumer stopping, or cancellation.
        case stopped
    }

    /// `task` is already open so `send` can use it before serving starts.
    init(log: BeamLogger, id: String, pingInterval: Duration?, task: URLSessionWebSocketTask) {
        self.log = log
        self.id = id
        self.pingInterval = pingInterval.flatMap { (.seconds(1) ... .seconds(300)).contains($0) ? $0 : nil }
        self.task = task
    }

    // MARK: - Handshake

    /// Returns a refused upgrade's response for `Endpoint` to validate; throws only without a response.
    static func handshake(
        _ request: URLRequest,
        session: any SessionProtocol,
        log: BeamLogger,
        id: String
    ) async throws(WebSocketError) -> (task: URLSessionWebSocketTask, response: HTTPURLResponse) {
        let task = session.webSocketTask(with: request)
        let handshake = WebSocketHandshake()
        task.delegate = handshake // must be set before `resume()`
        if let url = request.url {
            log.log(.wsOpen(id: id, url: url, headers: request.allHTTPHeaderFields))
        }
        task.resume()

        let outcome = await withTaskCancellationHandler {
            await handshake.outcome()
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }

        let response = task.response as? HTTPURLResponse
        switch outcome {
        case .success:
            guard let response else {
                task.cancel()
                throw .network(URLError(.badServerResponse))
            }
            return (task, response)
        case .failure(let error):
            if let response, response.httpStatus != .switchingProtocols {
                return (task, response)
            }
            throw .network(session.sessionDelegate.resolve(error, for: task))
        }
    }

    static func abandon(_ task: URLSessionWebSocketTask) {
        task.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Serve

    func serve(
        _ task: URLSessionWebSocketTask,
        deliver: @Sendable (URLSessionWebSocketTask.Message) -> Bool
    ) async -> Ending {
        guard !isClosed else {
            Self.abandon(task)
            return .stopped
        }
        self.task = task
        defer { if self.task === task { self.task = nil } }

        let pingInterval = self.pingInterval
        let log = self.log
        let id = self.id

        let ending = await withTaskGroup(of: Bool.self, returning: Ending.self) { group in
            if let pingInterval {
                group.addTask {
                    await Self.keepAlive(task, every: pingInterval, log: log, id: id)
                }
            }
            let ending = await receiveMessages(from: task, deliver: deliver)
            // Before closing, so a ping released by the close isn't taken as failed.
            group.cancelAll()
            // Also releases a ping waiting for its pong.
            if task.state == .running { Self.abandon(task) }
            // A failed ping caused the drop: report the ping.
            if case .dropped = ending {
                for await pingFailed in group where pingFailed {
                    return .dropped(.pingFailed)
                }
            }
            return ending
        }
        return isClosed || Task.isCancelled ? .stopped : ending
    }

    private func receiveMessages(
        from task: URLSessionWebSocketTask,
        deliver: @Sendable (URLSessionWebSocketTask.Message) -> Bool
    ) async -> Ending {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                // `receive()` ignores Swift task cancellation; cancelling the socket releases it.
                message = try await withTaskCancellationHandler {
                    try await task.receive()
                } onCancel: {
                    Self.abandon(task)
                }
            } catch {
                switch task.closeCode {
                case .invalid:
                    return .dropped(.network(URLError(bridging: error)))
                case .normalClosure, .goingAway:
                    return .closed
                case let code:
                    let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
                    return .dropped(.closed(code: code, reason: reason))
                }
            }

            let (type, body): (String, LogEvent.Body) = switch message {
            case .string(let text): ("text", .data(Data(text.utf8)))
            case .data(let data): ("binary", .data(data))
            @unknown default: ("unknown", .none)
            }
            log.log(.wsReceive(id: id, type: type, body: body))

            guard deliver(message) else { return .stopped }
        }
    }

    // MARK: - Send

    func send(data: Data) async throws(WebSocketError) {
        try await send(.data(data), type: "binary", logged: data)
    }

    func send(text: String) async throws(WebSocketError) {
        try await send(.string(text), type: "text", logged: Data(text.utf8))
    }

    private func send(_ message: URLSessionWebSocketTask.Message, type: String, logged body: Data) async throws(WebSocketError) {
        guard let task, task.state == .running else {
            throw .closed(code: .abnormalClosure, reason: nil)
        }
        do {
            try await task.send(message)
        } catch {
            throw .sendFailed(URLError(bridging: error))
        }
        log.log(.wsSend(id: id, type: type, body: .data(body)))
    }

    // MARK: - Close

    /// The connection ended on its own; a later `close` is a no-op.
    func end() {
        isClosed = true
        task = nil
    }

    func close(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) {
        guard !isClosed else { return }
        isClosed = true

        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) }
        log.log(.wsClose(id: id, code: code.rawValue, reason: reasonStr))
        task?.cancel(with: code, reason: reason)
        task = nil
    }

    // MARK: - Ping

    /// Returns `true` if a ping failed; it then closes the socket so the receive loop ends.
    private static func keepAlive(_ task: URLSessionWebSocketTask, every interval: Duration, log: BeamLogger, id: String) async -> Bool {
        while true {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return false
            }

            let failed = await withCheckedContinuation { (pong: CheckedContinuation<Bool, Never>) in
                task.sendPing { error in pong.resume(returning: error != nil) }
            }
            // A ping released by our own closing of the socket is not a failure.
            guard !Task.isCancelled else { return false }
            guard !failed else {
                task.cancel(with: .abnormalClosure, reason: nil)
                return true
            }
            log.log(.wsPing(id: id))
        }
    }
}

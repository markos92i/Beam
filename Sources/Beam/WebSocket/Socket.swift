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
import Logy

actor Socket {
    private let log: BeamLogger
    private let id: String
    private let config: SocketConfig

    private var task: URLSessionWebSocketTask?

    private var isClosed = false

    enum Ending: Sendable {
        /// The server closed with 1000.
        case closed
        case dropped(WebSocketError)
        /// `close`, the consumer stopping, or cancellation.
        case stopped
    }

    /// `task` is already open so `send` can use it before serving starts.
    init(log: BeamLogger, id: String, config: SocketConfig, task: URLSessionWebSocketTask) {
        self.log = log
        self.id = id
        self.config = config
        self.task = task
    }

    // MARK: - Handshake

    /// Returns a refused upgrade's response for `Endpoint` to validate; throws only without a response.
    static func handshake(
        _ request: URLRequest,
        config: SocketConfig,
        session: any SessionProtocol,
        log: BeamLogger,
        id: String
    ) async throws(WebSocketError) -> (task: URLSessionWebSocketTask, response: HTTPURLResponse, protocol: String?) {
        var request = request
        if !config.protocols.isEmpty {
            request.setValue(config.protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = config.maxMessageSize
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
        case .success(let chosen):
            guard let response else {
                task.cancel()
                throw .network(URLError(.badServerResponse))
            }
            return (task, response, chosen)
        case .failure(let error):
            if let response, response.httpStatus != .switchingProtocols {
                return (task, response, nil)
            }
            throw .network(session.sessionDelegate.resolve(error, for: task))
        }
    }

    static func abandon(_ task: URLSessionWebSocketTask) {
        task.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Serve

    /// Hands each message to `deliver`, off the actor, until the connection ends.
    func serve(
        _ task: URLSessionWebSocketTask,
        deliver: @escaping @concurrent @Sendable (URLSessionWebSocketTask.Message) async -> Void
    ) async -> Ending {
        guard !isClosed else {
            Self.abandon(task)
            return .stopped
        }
        self.task = task
        defer { if self.task === task { self.task = nil } }

        let (log, id, config) = (log, id, config)
        let ending = await withTaskGroup(of: Bool.self, returning: Ending.self) { group in
            if let interval = config.pingInterval {
                group.addTask {
                    await Self.keepAlive(task, every: interval, pongTimeout: config.pongTimeout ?? interval, log: log, id: id)
                }
            }
            let ending = await Self.receiveMessages(from: task, limit: config.maxMessageSize, log: log, id: id, deliver: deliver)
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

    private static func receiveMessages(
        from task: URLSessionWebSocketTask,
        limit: Int,
        log: BeamLogger,
        id: String,
        deliver: @concurrent @Sendable (URLSessionWebSocketTask.Message) async -> Void
    ) async -> Ending {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                // `receive()` ignores Swift task cancellation; cancelling the socket releases it.
                message = try await withTaskCancellationHandler {
                    try await task.receive()
                } onCancel: {
                    abandon(task)
                }
            } catch {
                let code = task.closeCode
                guard code != .invalid else { return .dropped(drop(error, limit: limit)) }
                let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
                log.log(.wsClose(id: id, code: code.rawValue, reason: reason))
                return code == .normalClosure ? .closed : .dropped(.closed(code: code, reason: reason))
            }

            let (type, body): (String, LogEvent.Body) = switch message {
            case .string(let text): ("text", .data(Data(text.utf8)))
            case .data(let data): ("binary", .data(data))
            @unknown default: ("unknown", .none)
            }
            log.log(.wsReceive(id: id, type: type, body: body))
            await deliver(message)
        }
    }

    /// URLSession reports a lost connection, and a message over its limit, as POSIX errors.
    private static func drop(_ error: any Error, limit: Int) -> WebSocketError {
        let posix = error as NSError
        switch (posix.domain, posix.code) {
        case (NSPOSIXErrorDomain, Int(EMSGSIZE)): return .messageTooLarge(limit: limit)
        case (NSPOSIXErrorDomain, _): return .unexpectedDisconnection
        default: return .network(URLError(bridging: error))
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
        guard let task, task.state == .running else { throw .notConnected }
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

    /// Returns `true` if the ping got no pong in time; it then closes the socket so the receive loop ends.
    private static func keepAlive(_ task: URLSessionWebSocketTask, every interval: Duration, pongTimeout: Duration, log: BeamLogger, id: String) async -> Bool {
        while true {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return false
            }

            // `true` for a pong, `false` for an error, `nil` when it took longer than `pongTimeout`.
            let pong = await withTaskGroup(of: Bool?.self) { group in
                group.addTask {
                    await withCheckedContinuation { continuation in
                        task.sendPing { error in continuation.resume(returning: error == nil) }
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: pongTimeout)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                // Releases the ping still waiting for its pong.
                if first == nil, !Task.isCancelled { task.cancel(with: .abnormalClosure, reason: nil) }
                return first
            }
            // A ping released by our own closing of the socket is not a failure.
            guard !Task.isCancelled else { return false }
            guard pong == true else {
                task.cancel(with: .abnormalClosure, reason: nil)
                return true
            }
            log.log(.wsPing(id: id))
        }
    }
}

//
//  WebSocketConnection.swift
//  Beam
//
//  A live WebSocket connection that provides a message stream,
//  send capabilities, and disconnect control.
//

import Foundation
import Logy

/// A live WebSocket connection returned by `@Socket` methods: `Incoming` messages are
/// received, `Outgoing` ones sent. Releasing it and its `messages` closes the socket.
public struct WebSocketConnection<Incoming: Sendable, Outgoing: Sendable, Failure: Sendable>: Sendable {
    /// Decoded messages across reconnections; throws the error that ended the connection.
    public let messages: ThrowingStream<Incoming, APIError<Failure>>

    /// Lifecycle changes; only the latest is buffered.
    public let state: AsyncStream<WebSocketConnectionState>

    /// The subprotocol the server chose, if any.
    public let `protocol`: String?

    let json: JSONCoding
    let jsonFrames: SocketConfig.JSONFrames
    let log: BeamLogger
    let id: String
    let transport: Transport

    enum Transport: Sendable {
        case socket(Socket, run: Task<Void, Never>)
        /// No server: sends go to `send`, `disconnect()` calls `close`.
        case mock(send: @Sendable (Outgoing) -> Void, close: @Sendable () -> Void)
    }

    /// Fails with `.connection(.notConnected)` while reconnecting or after the connection ended.
    public func send(data: Data) async throws(APIError<Failure>) {
        guard case .socket(let socket, _) = transport else { return }
        do throws(WebSocketError) { try await socket.send(data: data) } catch { throw APIError(error) }
    }

    public func send(text: String) async throws(APIError<Failure>) {
        guard case .socket(let socket, _) = transport else { return }
        do throws(WebSocketError) { try await socket.send(text: text) } catch { throw APIError(error) }
    }

    /// Closes with `.normalClosure`.
    public func disconnect() async {
        switch transport {
        case .socket(let socket, let run):
            // Socket first, so the server gets this code rather than a cancelled receive's `.goingAway`.
            await socket.close(code: .normalClosure)
            run.cancel()
        case .mock(_, let close):
            close()
        }
    }
}

extension WebSocketConnection where Outgoing: Encodable {
    /// Sends `value` as JSON, in the frame `SocketConfig.jsonFrames` says.
    public func send(_ value: Outgoing) async throws(APIError<Failure>) {
        if case .mock(let send, _) = transport { return send(value) }
        let data = try await Self.encode(value, json: json, log: log, id: id)
        switch jsonFrames {
        case .text: try await send(text: String(decoding: data, as: UTF8.self))
        case .binary: try await send(data: data)
        }
    }

    /// `@concurrent` so a main-actor caller doesn't encode on the main actor.
    @concurrent
    private static func encode(_ value: Outgoing, json: JSONCoding, log: BeamLogger, id: String) async throws(APIError<Failure>) -> Data {
        do {
            return try json.encode(value)
        } catch {
            log.log(.codingFailed(id: id, what: "WebSocket message not encoded", detail: error.logDescription))
            throw .coding(error)
        }
    }
}

extension WebSocketConnection where Outgoing == String {
    /// Sends `value` unencoded as a text message.
    public func send(_ value: String) async throws(APIError<Failure>) {
        if case .mock(let send, _) = transport { return send(value) }
        try await send(text: value)
    }
}

// MARK: - Mock

extension WebSocketConnection {
    /// A connection without a server, for previews and tests: it yields `messages`, then stays
    /// open until `disconnect()`, or ends with `failure`. What the app sends goes to `onSend`.
    public static func mock(
        _ messages: [Incoming] = [],
        failure: APIError<Failure>? = nil,
        protocol: String? = nil,
        onSend: @escaping @Sendable (Outgoing) -> Void = { _ in }
    ) -> Self {
        let (stream, events) = ThrowingStream<Incoming, APIError<Failure>>.makeStream()
        let (state, states) = AsyncStream<WebSocketConnectionState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        for message in messages { events.yield(message) }
        states.yield(.connected)
        let end: @Sendable (DisconnectionReason, APIError<Failure>?) -> Void = { reason, failure in
            states.yield(.disconnected(reason: reason))
            states.finish()
            events.finish(throwing: failure)
        }
        if let failure { end(.error(failure.asVoid.kind), failure) }
        return Self(
            messages: stream, state: state, protocol: `protocol`, json: .default, jsonFrames: .text,
            log: BeamLogger(), id: "mock", transport: .mock(send: onSend, close: { end(.intentional, nil) })
        )
    }
}

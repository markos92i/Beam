//
//  WebSocketConnection.swift
//  Beam
//
//  A live WebSocket connection that provides a message stream,
//  send capabilities, and disconnect control.
//

import Foundation

/// A live WebSocket connection returned by `@Socket` methods.
///
/// Provides:
/// - `messages`: An `AsyncThrowingStream` of decoded messages and connection events.
/// - `state`: An `AsyncStream` of connection state changes (connecting, connected, reconnecting, disconnected).
/// - `send(_:)`: Send a typed value to the server.
/// - `disconnect()`: Gracefully close the connection.
///
/// Usage:
/// ```swift
/// let connection = try await api.chat()
///
/// // Observe messages
/// Task {
///     for try await event in connection.messages {
///         switch event {
///         case .message(let msg): handleMessage(msg)
///         case .reconnecting: showReconnecting()
///         case .reconnected: hideReconnecting()
///         }
///     }
/// }
///
/// // Send a message
/// try await connection.send(ChatMessage(text: "hola"))
///
/// // Disconnect when done
/// await connection.disconnect()
/// ```
public struct WebSocketConnection<Success: Sendable, Failure: Sendable>: Sendable {

    /// Stream of incoming messages and connection lifecycle events.
    public let messages: AsyncThrowingStream<StreamEvent<Success, Failure>, Error>

    /// Observable stream of connection state changes.
    /// Yields state transitions (connecting, connected, reconnecting, disconnected).
    public let state: AsyncStream<WebSocketConnectionState>

    private let _send: @Sendable (Success) async throws -> Void
    private let _sendData: @Sendable (Data) async throws -> Void
    private let _sendText: @Sendable (String) async throws -> Void
    private let _disconnect: @Sendable () async -> Void

    init(
        messages: AsyncThrowingStream<StreamEvent<Success, Failure>, Error>,
        state: AsyncStream<WebSocketConnectionState>,
        send: @escaping @Sendable (Success) async throws -> Void,
        sendData: @escaping @Sendable (Data) async throws -> Void,
        sendText: @escaping @Sendable (String) async throws -> Void,
        disconnect: @escaping @Sendable () async -> Void
    ) {
        self.messages = messages
        self.state = state
        self._send = send
        self._sendData = sendData
        self._sendText = sendText
        self._disconnect = disconnect
    }

    /// Sends a typed value as a JSON-encoded binary message.
    public func send(_ value: Success) async throws {
        try await _send(value)
    }

    /// Sends raw data as a binary message.
    public func send(data: Data) async throws {
        try await _sendData(data)
    }

    /// Sends a string as a text message.
    public func send(text: String) async throws {
        try await _sendText(text)
    }

    /// Gracefully disconnects the WebSocket.
    public func disconnect() async {
        await _disconnect()
    }
}

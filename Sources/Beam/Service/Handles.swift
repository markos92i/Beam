//
//  Handles.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

// MARK: - StreamHandle

/// A typed handle for WebSocket operations. Provides connect, send, disconnect, and ping.
///
/// Usage:
/// ```swift
/// let socket = api.chat(roomId: "room-42")
/// let stream = try await socket.connect()
///
/// for try await event in stream {
///     switch event {
///     case .message(let msg): handleMessage(msg)
///     case .reconnecting(let attempt, _): showReconnecting(attempt)
///     case .reconnected: hideReconnecting()
///     }
/// }
///
/// try await socket.send(ChatMessage(text: "Hola"))
/// await socket.disconnect()
/// ```
public struct StreamHandle<Success: Sendable, Failure: Sendable>: Sendable {
    public let service: Service<Success, Failure>

    public init(service: Service<Success, Failure>) {
        self.service = service
    }

    /// Opens the WebSocket connection with automatic reconnection.
    public func connect() async throws(APIError<Failure>) -> AsyncThrowingStream<StreamEvent<Success, Failure>, Error> {
        try await service.stream()
    }

    /// Sends a typed value over the WebSocket.
    public func send(_ value: Success) async throws(APIError<Failure>) {
        try await service.send(value)
    }

    /// Sends raw data as a binary message.
    public func send(data: Data) async throws(APIError<Failure>) {
        try await service.send(data: data)
    }

    /// Sends a string as a text message.
    public func send(text: String) async throws(APIError<Failure>) {
        try await service.send(text: text)
    }

    /// Disconnects the WebSocket.
    public func disconnect(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) async {
        await service.disconnect(code: code, reason: reason)
    }

    /// Sends a ping frame.
    public func ping() async throws(APIError<Failure>) {
        try await service.ping()
    }
}

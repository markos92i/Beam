//
//  WebSocketError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 17/06/2026.
//

import Foundation

/// Errors specific to WebSocket connections.
///
/// Provides semantic meaning for connection lifecycle failures,
/// separating them from HTTP transport errors.
public enum WebSocketError: Error, LoggableError {
    /// The connection closed with a non-normal close code.
    case closed(code: URLSessionWebSocketTask.CloseCode, reason: String?)

    /// The connection dropped unexpectedly (no close frame received).
    case unexpectedDisconnection

    /// A network-level error occurred on the WebSocket connection.
    case network(URLError)

    /// Failed to send a message (connection not active or write error).
    case sendFailed(Error)

    /// Ping/pong failed (connection likely dead).
    case pingFailed

    // MARK: - LoggableError

    var logDescription: String {
        switch self {
        case .closed(let code, let reason):
            let reasonStr = reason.map { ": \($0)" } ?? ""
            return "WebSocket closed with code \(code.rawValue)\(reasonStr)"
        case .unexpectedDisconnection:
            return "WebSocket disconnected unexpectedly (no close frame)"
        case .network(let error):
            return "WebSocket network error: \(error.localizedDescription)"
        case .sendFailed(let error):
            return "WebSocket send failed: \(error.localizedDescription)"
        case .pingFailed:
            return "WebSocket ping failed — connection likely dead"
        }
    }

    // MARK: - Reconnection

    /// Whether this error is transient and the connection should attempt reconnection.
    var isReconnectable: Bool {
        switch self {
        case .closed(let code, _):
            // Normal closure and going away are intentional — don't reconnect
            code != .normalClosure && code != .goingAway
        case .unexpectedDisconnection:
            true
        case .network(let error):
            [.networkConnectionLost, .timedOut, .notConnectedToInternet].contains(error.code)
        case .sendFailed:
            false
        case .pingFailed:
            true
        }
    }

    // MARK: - Factory

    /// Maps a raw WebSocket receive/send error to a typed `WebSocketError`.
    static func from(_ error: Error) -> WebSocketError {
        if let urlError = error as? URLError {
            return .network(urlError)
        }
        return .unexpectedDisconnection
    }
}

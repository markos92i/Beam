//
//  WebSocketError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 17/06/2026.
//

import Foundation

/// Failures of the WebSocket transport (`Socket`).
public enum WebSocketError: Error, LoggableError {
    /// The server closed with a code other than 1000.
    case closed(code: URLSessionWebSocketTask.CloseCode, reason: String?)
    /// The connection went away without a close frame.
    case unexpectedDisconnection
    /// No pong arrived in time.
    case pingFailed
    /// A message was bigger than `SocketConfig.maxMessageSize`.
    case messageTooLarge(limit: Int)
    /// Sent while there is no open connection: before it opens, reconnecting, or closed.
    case notConnected
    case network(URLError)
    case sendFailed(URLError)

    // MARK: - LoggableError

    var logDescription: String {
        switch self {
        case .closed(let code, let reason):
            "WebSocket closed with code \(code.rawValue)\(reason.map { ": \($0)" } ?? "")"
        case .unexpectedDisconnection:
            "WebSocket disconnected unexpectedly (no close frame)"
        case .pingFailed:
            "WebSocket ping got no pong in time"
        case .messageTooLarge(let limit):
            "WebSocket message bigger than \(limit.byteFormatted)"
        case .notConnected:
            "WebSocket not connected"
        case .network(let error):
            "WebSocket network error: \(error.logDescription)"
        case .sendFailed(let error):
            "WebSocket send failed: \(error.logDescription)"
        }
    }

    /// Whether a dropped connection is re-established.
    func reconnects(with config: SocketConfig) -> Bool {
        switch self {
        case .closed(let code, _): config.reconnects(after: code.rawValue)
        case .unexpectedDisconnection, .pingFailed: true
        case .network(let error): error.isTransient
        case .messageTooLarge, .notConnected, .sendFailed: false
        }
    }

    /// Whether a failed handshake is worth repeating.
    var isRetryable: Bool {
        if case .network(let error) = self { error.isTransient } else { false }
    }
}

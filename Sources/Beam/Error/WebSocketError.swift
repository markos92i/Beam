//
//  WebSocketError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 17/06/2026.
//

import Foundation

/// Failures of the WebSocket transport (`Socket`).
public enum WebSocketError: Error, LoggableError {
    case closed(code: URLSessionWebSocketTask.CloseCode, reason: String?)

    case unexpectedDisconnection

    case pingFailed

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
            "WebSocket ping failed — connection likely dead"
        case .network(let error):
            "WebSocket network error: \(error.logDescription)"
        case .sendFailed(let error):
            "WebSocket send failed: \(error.logDescription)"
        }
    }

    // MARK: - Retry

    /// `.closed` is always a drop: `Socket` ends a normal closure (1000, 1001) without an error.
    var isRetryable: Bool {
        switch self {
        case .closed, .unexpectedDisconnection, .pingFailed:
            true
        case .network(let error):
            error.isTransient
        case .sendFailed:
            false
        }
    }
}

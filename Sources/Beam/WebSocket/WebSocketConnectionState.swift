//
//  WebSocketConnectionState.swift
//  Beam
//
//  Observable connection state for WebSocket lifecycle tracking.
//

import Foundation

// MARK: - DisconnectionReason

/// Why a WebSocket connection ended.
public enum DisconnectionReason: Sendable, Equatable {
    /// The server closed normally (1000).
    case closed
    /// `disconnect()` was called, or the connection was released.
    case intentional
    /// The full error is thrown by `messages`.
    case error(APIErrorKind)
}

// MARK: - WebSocketConnectionState

/// Lifecycle of an open WebSocket connection, observed via `WebSocketConnection.state`.
public enum WebSocketConnectionState: Sendable, Equatable {
    case connected
    /// `attempt` counts the reconnection policy's retries since the connection was last stable.
    case reconnecting(attempt: Int, maxAttempts: Int)
    case disconnected(reason: DisconnectionReason)
}

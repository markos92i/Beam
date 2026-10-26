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
    /// The server closed normally.
    case closed
    /// `disconnect()` was called.
    case intentional
    /// The full error is thrown by `messages`.
    case error(APIErrorKind)
}

// MARK: - WebSocketConnectionState

/// Lifecycle of a WebSocket connection, observed via `WebSocketConnection.state`.
public enum WebSocketConnectionState: Sendable, Equatable {
    /// Establishing the first connection.
    case connecting
    case connected
    case reconnecting(attempt: Int, maxAttempts: Int)
    case disconnected(reason: DisconnectionReason)
}

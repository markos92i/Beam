//
//  WebSocketConnectionState.swift
//  Beam
//
//  Observable connection state for WebSocket lifecycle tracking.
//

import Foundation

// MARK: - DisconnectionReason

/// Reason why a WebSocket connection was disconnected.
public enum DisconnectionReason: Sendable, Equatable {
    /// Server or network closed the connection normally.
    case closed
    /// The client intentionally disconnected (e.g., called `disconnect()`).
    case intentional
    /// An error caused the disconnection. Uses `String` for `Equatable` conformance.
    case error(String)
}

// MARK: - WebSocketConnectionState

/// Observable state of a WebSocket connection lifecycle.
///
/// Consumers can observe state transitions via `WebSocketConnection.state` to drive UI
/// (e.g., showing a reconnecting banner or disabling send buttons).
public enum WebSocketConnectionState: Sendable, Equatable {
    /// The WebSocket is attempting to establish the initial connection.
    case connecting
    /// The WebSocket connection is active and ready.
    case connected
    /// The WebSocket lost connection and is retrying.
    case reconnecting(attempt: Int, maxAttempts: Int)
    /// The WebSocket is disconnected.
    case disconnected(reason: DisconnectionReason)
}

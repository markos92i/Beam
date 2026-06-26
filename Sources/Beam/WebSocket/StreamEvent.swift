//
//  StreamEvent.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 14/06/2026.
//

import Foundation

/// Events emitted by a WebSocket connection stream.
public enum StreamEvent<Success: Sendable, Failure: Sendable>: Sendable {
    case message(Success)
    case reconnecting(attempt: Int, maxAttempts: Int)
    case reconnected
}

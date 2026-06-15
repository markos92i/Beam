//
//  RetryPolicy.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 14/06/2026.
//

import Foundation

// MARK: - RetryPolicy

public struct RetryPolicy: Sendable, Equatable {
    public let strategy: Strategy
    public let maxAttempts: Int

    public init(strategy: Strategy = .none, maxAttempts: Int = 1) {
        self.strategy = strategy
        self.maxAttempts = max(0, maxAttempts)
    }

    /// No retries at all.
    public static let none = RetryPolicy(strategy: .none, maxAttempts: 0)

    /// Default: 1 immediate retry. Good for transient failures (timeouts, token refresh).
    public static let standard = RetryPolicy(strategy: .none, maxAttempts: 1)

    /// Resilient: 3 retries with exponential backoff (1s, 2s, 4s). Suitable for critical requests
    /// or WebSocket reconnection where you want to ride out brief connectivity blips.
    public static let resilient = RetryPolicy(strategy: .exponential(base: 1, maxDelay: 10), maxAttempts: 3)

    /// Convenience for linear backoff.
    public static func linear(delay: TimeInterval, maxAttempts: Int) -> RetryPolicy {
        RetryPolicy(strategy: .linear(delay: delay), maxAttempts: maxAttempts)
    }

    /// Convenience for exponential backoff.
    public static func exponential(base: TimeInterval, maxDelay: TimeInterval, maxAttempts: Int) -> RetryPolicy {
        RetryPolicy(strategy: .exponential(base: base, maxDelay: maxDelay), maxAttempts: maxAttempts)
    }

    public func delay(for attempt: Int) -> TimeInterval {
        strategy.delay(for: attempt)
    }

    // MARK: - Strategy

    public enum Strategy: Sendable, Equatable {
        case none
        case linear(delay: TimeInterval)
        case exponential(base: TimeInterval, maxDelay: TimeInterval)

        public func delay(for attempt: Int) -> TimeInterval {
            switch self {
            case .none: 0
            case .linear(let delay): delay
            case .exponential(let base, let maxDelay): min(base * pow(2.0, Double(attempt - 1)), maxDelay)
            }
        }
    }
}

// MARK: - StreamEvent

public enum StreamEvent<Success: Sendable, Failure: Sendable>: Sendable {
    case message(Success)
    case reconnecting(attempt: Int, maxAttempts: Int)
    case reconnected
}

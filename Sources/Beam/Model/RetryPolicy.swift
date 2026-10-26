//
//  RetryPolicy.swift
//  Beam
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

    /// No retries.
    public static let none = RetryPolicy(strategy: .none, maxAttempts: 0)

    /// One immediate retry.
    public static let standard = RetryPolicy(strategy: .none, maxAttempts: 1)

    /// 3 retries with exponential backoff (1s, 2s, 4s).
    public static let resilient = RetryPolicy(strategy: .exponential(base: .seconds(1), maxDelay: .seconds(10)), maxAttempts: 3)

    /// Convenience for linear backoff.
    public static func linear(delay: Duration, maxAttempts: Int) -> RetryPolicy {
        RetryPolicy(strategy: .linear(delay: delay), maxAttempts: maxAttempts)
    }

    /// Convenience for exponential backoff.
    public static func exponential(base: Duration, maxDelay: Duration, maxAttempts: Int) -> RetryPolicy {
        RetryPolicy(strategy: .exponential(base: base, maxDelay: maxDelay), maxAttempts: maxAttempts)
    }

    /// Delay before the given retry attempt (1-based).
    public func delay(for attempt: Int) -> Duration {
        strategy.delay(for: attempt)
    }

    // MARK: - Strategy

    public enum Strategy: Sendable, Equatable {
        case none
        case linear(delay: Duration)
        case exponential(base: Duration, maxDelay: Duration)

        public func delay(for attempt: Int) -> Duration {
            switch self {
            case .none:
                .zero
            case .linear(let delay):
                delay
            case .exponential(let base, let maxDelay):
                // Exponent clamped to avoid overflow.
                min(base * (1 << max(0, min(attempt - 1, 30))), maxDelay)
            }
        }
    }
}

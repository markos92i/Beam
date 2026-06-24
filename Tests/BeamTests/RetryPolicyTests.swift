//
//  RetryPolicyTests.swift
//  Beam
//

import Foundation
import Testing
@testable import Beam

@Suite
struct RetryPolicyTests {

    // MARK: - Strategy.none

    @Test
    func noneStrategyReturnsZeroForAnyAttempt() {
        let strategy = RetryPolicy.Strategy.none
        #expect(strategy.delay(for: 1) == 0)
        #expect(strategy.delay(for: 2) == 0)
        #expect(strategy.delay(for: 5) == 0)
        #expect(strategy.delay(for: 100) == 0)
    }

    // MARK: - Strategy.linear

    @Test
    func linearStrategyReturnsFixedDelay() {
        let strategy = RetryPolicy.Strategy.linear(delay: 2.0)
        #expect(strategy.delay(for: 1) == 2.0)
        #expect(strategy.delay(for: 2) == 2.0)
        #expect(strategy.delay(for: 3) == 2.0)
        #expect(strategy.delay(for: 10) == 2.0)
    }

    // MARK: - Strategy.exponential

    @Test
    func exponentialStrategyReturnsBaseTimesExponent() {
        let strategy = RetryPolicy.Strategy.exponential(base: 1.0, maxDelay: 60.0)
        // base × 2^(attempt-1)
        #expect(strategy.delay(for: 1) == 1.0)   // 1 × 2^0 = 1
        #expect(strategy.delay(for: 2) == 2.0)   // 1 × 2^1 = 2
        #expect(strategy.delay(for: 3) == 4.0)   // 1 × 2^2 = 4
        #expect(strategy.delay(for: 4) == 8.0)   // 1 × 2^3 = 8
        #expect(strategy.delay(for: 5) == 16.0)  // 1 × 2^4 = 16
    }

    @Test
    func exponentialStrategyCapsAtMaxDelay() {
        let strategy = RetryPolicy.Strategy.exponential(base: 1.0, maxDelay: 10.0)
        // 1 × 2^3 = 8 (under cap)
        #expect(strategy.delay(for: 4) == 8.0)
        // 1 × 2^4 = 16, capped at 10
        #expect(strategy.delay(for: 5) == 10.0)
        // 1 × 2^5 = 32, capped at 10
        #expect(strategy.delay(for: 6) == 10.0)
    }

    @Test
    func exponentialWithCustomBase() {
        let strategy = RetryPolicy.Strategy.exponential(base: 0.5, maxDelay: 30.0)
        // 0.5 × 2^0 = 0.5
        #expect(strategy.delay(for: 1) == 0.5)
        // 0.5 × 2^1 = 1.0
        #expect(strategy.delay(for: 2) == 1.0)
        // 0.5 × 2^2 = 2.0
        #expect(strategy.delay(for: 3) == 2.0)
    }

    // MARK: - Preset policies

    @Test
    func nonePolicyHasZeroMaxAttempts() {
        let policy = RetryPolicy.none
        #expect(policy.maxAttempts == 0)
        #expect(policy.strategy == .none)
    }

    @Test
    func standardPolicyHasOneMaxAttempt() {
        let policy = RetryPolicy.standard
        #expect(policy.maxAttempts == 1)
        #expect(policy.strategy == .none)
    }

    @Test
    func resilientPolicyHasThreeMaxAttempts() {
        let policy = RetryPolicy.resilient
        #expect(policy.maxAttempts == 3)
        #expect(policy.strategy == .exponential(base: 1, maxDelay: 10))
    }

    // MARK: - Convenience constructors + delay forwarding

    @Test
    func linearConvenienceConstructorSetsStrategyAndMaxAttempts() {
        let policy = RetryPolicy.linear(delay: 1.5, maxAttempts: 4)
        #expect(policy.strategy == .linear(delay: 1.5))
        #expect(policy.maxAttempts == 4)
    }

    @Test
    func exponentialConvenienceConstructorSetsStrategyAndMaxAttempts() {
        let policy = RetryPolicy.exponential(base: 2.0, maxDelay: 20.0, maxAttempts: 5)
        #expect(policy.strategy == .exponential(base: 2.0, maxDelay: 20.0))
        #expect(policy.maxAttempts == 5)
    }

    @Test
    func policyDelayForwardsToStrategy() {
        let linear = RetryPolicy(strategy: .linear(delay: 3.0), maxAttempts: 2)
        #expect(linear.delay(for: 1) == 3.0)
        #expect(linear.delay(for: 2) == 3.0)

        let exponential = RetryPolicy.exponential(base: 2.0, maxDelay: 20.0, maxAttempts: 5)
        #expect(exponential.delay(for: 1) == 2.0)  // 2 × 2^0
        #expect(exponential.delay(for: 4) == 16.0) // 2 × 2^3
        #expect(exponential.delay(for: 5) == 20.0) // capped
    }
}

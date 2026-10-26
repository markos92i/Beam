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
        #expect(strategy.delay(for: 1) == .zero)
        #expect(strategy.delay(for: 2) == .zero)
        #expect(strategy.delay(for: 5) == .zero)
        #expect(strategy.delay(for: 100) == .zero)
    }

    // MARK: - Strategy.linear

    @Test
    func linearStrategyReturnsFixedDelay() {
        let strategy = RetryPolicy.Strategy.linear(delay: .seconds(2))
        #expect(strategy.delay(for: 1) == .seconds(2))
        #expect(strategy.delay(for: 2) == .seconds(2))
        #expect(strategy.delay(for: 3) == .seconds(2))
        #expect(strategy.delay(for: 10) == .seconds(2))
    }

    // MARK: - Strategy.exponential

    @Test
    func exponentialStrategyReturnsBaseTimesExponent() {
        let strategy = RetryPolicy.Strategy.exponential(base: .seconds(1), maxDelay: .seconds(60))
        // base × 2^(attempt-1)
        #expect(strategy.delay(for: 1) == .seconds(1))   // 1 × 2^0 = 1
        #expect(strategy.delay(for: 2) == .seconds(2))   // 1 × 2^1 = 2
        #expect(strategy.delay(for: 3) == .seconds(4))   // 1 × 2^2 = 4
        #expect(strategy.delay(for: 4) == .seconds(8))   // 1 × 2^3 = 8
        #expect(strategy.delay(for: 5) == .seconds(16))  // 1 × 2^4 = 16
    }

    @Test
    func exponentialStrategyCapsAtMaxDelay() {
        let strategy = RetryPolicy.Strategy.exponential(base: .seconds(1), maxDelay: .seconds(10))
        // 1 × 2^3 = 8 (under cap)
        #expect(strategy.delay(for: 4) == .seconds(8))
        // 1 × 2^4 = 16, capped at 10
        #expect(strategy.delay(for: 5) == .seconds(10))
        // 1 × 2^5 = 32, capped at 10
        #expect(strategy.delay(for: 6) == .seconds(10))
    }

    @Test
    func exponentialWithCustomBase() {
        let strategy = RetryPolicy.Strategy.exponential(base: .milliseconds(500), maxDelay: .seconds(30))
        // 0.5 × 2^0 = 0.5
        #expect(strategy.delay(for: 1) == .milliseconds(500))
        // 0.5 × 2^1 = 1.0
        #expect(strategy.delay(for: 2) == .seconds(1))
        // 0.5 × 2^2 = 2.0
        #expect(strategy.delay(for: 3) == .seconds(2))
    }

    @Test
    func exponentialDoesNotOverflowForLargeAttempts() {
        let strategy = RetryPolicy.Strategy.exponential(base: .seconds(1), maxDelay: .seconds(10))
        #expect(strategy.delay(for: 1_000) == .seconds(10))
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
        #expect(policy.strategy == .exponential(base: .seconds(1), maxDelay: .seconds(10)))
    }

    // MARK: - Convenience constructors + delay forwarding

    @Test
    func linearConvenienceConstructorSetsStrategyAndMaxAttempts() {
        let policy = RetryPolicy.linear(delay: .milliseconds(1500), maxAttempts: 4)
        #expect(policy.strategy == .linear(delay: .milliseconds(1500)))
        #expect(policy.maxAttempts == 4)
    }

    @Test
    func exponentialConvenienceConstructorSetsStrategyAndMaxAttempts() {
        let policy = RetryPolicy.exponential(base: .seconds(2), maxDelay: .seconds(20), maxAttempts: 5)
        #expect(policy.strategy == .exponential(base: .seconds(2), maxDelay: .seconds(20)))
        #expect(policy.maxAttempts == 5)
    }

    @Test
    func policyDelayForwardsToStrategy() {
        let linear = RetryPolicy(strategy: .linear(delay: .seconds(3)), maxAttempts: 2)
        #expect(linear.delay(for: 1) == .seconds(3))
        #expect(linear.delay(for: 2) == .seconds(3))

        let exponential = RetryPolicy.exponential(base: .seconds(2), maxDelay: .seconds(20), maxAttempts: 5)
        #expect(exponential.delay(for: 1) == .seconds(2))  // 2 × 2^0
        #expect(exponential.delay(for: 4) == .seconds(16)) // 2 × 2^3
        #expect(exponential.delay(for: 5) == .seconds(20)) // capped
    }

    // MARK: - Foundation bridging

    @Test
    func durationBridgesToTimeInterval() {
        #expect(Duration.seconds(30).timeInterval == 30)
        #expect(Duration.milliseconds(1500).timeInterval == 1.5)
    }
}

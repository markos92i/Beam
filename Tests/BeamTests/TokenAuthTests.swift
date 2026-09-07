//
//  TokenAuthTests.swift
//  Beam
//
//  Created by Kiro on 3/8/26.
//

import Foundation
import Testing
@testable import Beam

// MARK: - Token Tests

@Suite("TokenAuth.Token")
struct TokenAuthTokenTests {

    @Test("isValid returns true for future expiration")
    func isValidFutureExpiration() {
        let token = TokenAuth.Token(
            value: "test",
            expiration: Date.now.addingTimeInterval(3600)
        )
        #expect(token.isValid)
    }

    @Test("isValid returns false for past expiration")
    func isValidPastExpiration() {
        let token = TokenAuth.Token(
            value: "test",
            expiration: Date.now.addingTimeInterval(-1)
        )
        #expect(!token.isValid)
    }

    @Test("expiresIn convenience initializer")
    func expiresInInitializer() {
        let token = TokenAuth.Token(value: "test", expiresIn: 3600)
        #expect(token.isValid)
        #expect(token.expiration > Date.now)
    }

    @Test("token preserves value")
    func tokenPreservesValue() {
        let token = TokenAuth.Token(value: "my_jwt_token", expiresIn: 100)
        #expect(token.value == "my_jwt_token")
    }
}

// MARK: - State Machine Tests

@Suite("TokenAuth State Machine")
struct TokenAuthStateMachineTests {

    // MARK: - Initial State (Loading)

    @Test("authenticate waits when in loading state")
    func authenticateWaitsInLoadingState() async throws {
        let auth = TokenAuth(name: "Test") {
            throw AuthError.failedToRefreshToken
        }

        // Start authentication in background - it should wait
        let task = Task {
            var request = URLRequest(url: URL(string: "https://test.com")!)
            try await auth.authenticate(request: &request)
            return request
        }

        // Give it time to start waiting
        try await Task.sleep(for: .milliseconds(50))

        // Now set the token - this should unblock the waiting task
        await auth.set(token: .init(value: "resolved_token", expiresIn: 3600))

        let request = try await task.value
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer resolved_token")
    }

    // MARK: - Ready State

    @Test("authenticate returns token when ready with valid token")
    func authenticateReturnsValidToken() async throws {
        let auth = TokenAuth(name: "Test") {
            throw AuthError.failedToRefreshToken
        }

        await auth.set(token: .init(value: "valid_token", expiresIn: 3600))

        var request = URLRequest(url: URL(string: "https://test.com")!)
        try await auth.authenticate(request: &request)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer valid_token")
    }

    @Test("authenticate triggers refresh when token expired")
    func authenticateRefreshesExpiredToken() async throws {
        let refreshCalled = AtomicFlag()

        let auth = TokenAuth(name: "Test") {
            await refreshCalled.set()
            return .init(value: "refreshed_token", expiresIn: 3600)
        }

        // Set an expired token
        await auth.set(token: .init(value: "expired", expiration: Date.now.addingTimeInterval(-10)))

        var request = URLRequest(url: URL(string: "https://test.com")!)
        try await auth.authenticate(request: &request)

        #expect(await refreshCalled.value)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed_token")
    }

    // MARK: - Invalid State

    @Test("invalidate triggers refresh on next authenticate")
    func invalidateTriggersRefresh() async throws {
        let refreshCount = AtomicCounter()

        let auth = TokenAuth(name: "Test") {
            await refreshCount.increment()
            return .init(value: "new_token_\(await refreshCount.value)", expiresIn: 3600)
        }

        await auth.set(token: .init(value: "initial", expiresIn: 3600))

        // First request - should use initial token
        var request1 = URLRequest(url: URL(string: "https://test.com")!)
        try await auth.authenticate(request: &request1)
        #expect(request1.value(forHTTPHeaderField: "Authorization") == "Bearer initial")

        // Invalidate
        await auth.invalidate()

        // Second request - should refresh
        var request2 = URLRequest(url: URL(string: "https://test.com")!)
        try await auth.authenticate(request: &request2)
        #expect(request2.value(forHTTPHeaderField: "Authorization") == "Bearer new_token_1")
        #expect(await refreshCount.value == 1)
    }

    // MARK: - Empty State

    @Test("authenticate throws missingToken when cleared")
    func authenticateThrowsWhenCleared() async {
        let auth = TokenAuth(name: "Test") {
            return .init(value: "token", expiresIn: 3600)
        }

        await auth.set(token: .init(value: "initial", expiresIn: 3600))
        await auth.clear()

        var request = URLRequest(url: URL(string: "https://test.com")!)

        do {
            try await auth.authenticate(request: &request)
            Issue.record("Should have thrown")
        } catch let error as AuthError {
            #expect(error == .missingToken)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("clear cancels pending refresh")
    func clearCancelsPendingRefresh() async throws {
        let refreshStarted = AtomicFlag()

        let auth = TokenAuth(name: "Test") {
            await refreshStarted.set()
            try await Task.sleep(for: .seconds(10))
            return .init(value: "token", expiresIn: 3600)
        }

        await auth.set(token: .init(value: "expired", expiration: Date.now.addingTimeInterval(-1)))

        // Start refresh in background
        let task = Task {
            var request = URLRequest(url: URL(string: "https://test.com")!)
            try await auth.authenticate(request: &request)
        }

        // Wait for refresh to start
        try await Task.sleep(for: .milliseconds(50))

        // Clear should cancel the refresh
        await auth.clear()

        // The task should complete with an error
        do {
            try await task.value
            Issue.record("Should have thrown")
        } catch {
            // Expected - either cancelled or missingToken
        }
    }
}

// MARK: - Refresh Deduplication Tests

@Suite("TokenAuth Refresh Deduplication")
struct TokenAuthRefreshDeduplicationTests {

    @Test("concurrent requests share single refresh")
    func concurrentRequestsShareRefresh() async throws {
        let refreshCount = AtomicCounter()

        let auth = TokenAuth(name: "Test") {
            await refreshCount.increment()
            try await Task.sleep(for: .milliseconds(100))
            return .init(value: "shared_token", expiresIn: 3600)
        }

        // Set expired token to trigger refresh
        await auth.set(token: .init(value: "expired", expiration: Date.now.addingTimeInterval(-1)))

        // Launch 10 concurrent requests
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    var request = URLRequest(url: URL(string: "https://test.com")!)
                    try? await auth.authenticate(request: &request)
                }
            }
        }

        // Should only have called refresh once
        #expect(await refreshCount.value == 1)
    }

    @Test("sequential requests after refresh don't re-refresh")
    func sequentialRequestsAfterRefresh() async throws {
        let refreshCount = AtomicCounter()

        let auth = TokenAuth(name: "Test") {
            await refreshCount.increment()
            return .init(value: "token", expiresIn: 3600)
        }

        await auth.set(token: .init(value: "expired", expiration: Date.now.addingTimeInterval(-1)))

        // First request triggers refresh
        var request1 = URLRequest(url: URL(string: "https://test.com")!)
        try await auth.authenticate(request: &request1)

        // Subsequent requests use cached token
        for _ in 0..<5 {
            var request = URLRequest(url: URL(string: "https://test.com")!)
            try await auth.authenticate(request: &request)
        }

        #expect(await refreshCount.value == 1)
    }
}

// MARK: - Session Lost Callback Tests

@Suite("TokenAuth Session Lost")
struct TokenAuthSessionLostTests {

    @Test("onSessionLost called when refresh fails with invalidCredentials")
    func onSessionLostCalledOnInvalidCredentials() async throws {
        let sessionLostCalled = AtomicFlag()

        let auth = TokenAuth(
            name: "Test",
            refresh: { throw AuthError.invalidCredentials },
            onSessionLost: { await sessionLostCalled.set() }
        )

        await auth.set(token: .init(value: "expired", expiration: Date.now.addingTimeInterval(-1)))

        var request = URLRequest(url: URL(string: "https://test.com")!)

        do {
            try await auth.authenticate(request: &request)
            Issue.record("Should have thrown")
        } catch let error as AuthError {
            #expect(error == .invalidCredentials)
        } catch {
            Issue.record("Wrong error type")
        }

        #expect(await sessionLostCalled.value)
    }

    @Test("onSessionLost not called for other refresh errors")
    func onSessionLostNotCalledForOtherErrors() async throws {
        let sessionLostCalled = AtomicFlag()

        let auth = TokenAuth(
            name: "Test",
            refresh: { throw AuthError.failedToRefreshToken },
            onSessionLost: { await sessionLostCalled.set() }
        )

        await auth.set(token: .init(value: "expired", expiration: Date.now.addingTimeInterval(-1)))

        var request = URLRequest(url: URL(string: "https://test.com")!)

        do {
            try await auth.authenticate(request: &request)
            Issue.record("Should have thrown")
        } catch let error as AuthError {
            #expect(error == .failedToRefreshToken)
        } catch {
            Issue.record("Wrong error type")
        }

        #expect(await sessionLostCalled.value == false)
    }

    @Test("state becomes empty after invalidCredentials")
    func stateBecomesEmptyAfterInvalidCredentials() async throws {
        let auth = TokenAuth(name: "Test") {
            throw AuthError.invalidCredentials
        }

        await auth.set(token: .init(value: "expired", expiration: Date.now.addingTimeInterval(-1)))

        var request = URLRequest(url: URL(string: "https://test.com")!)
        _ = try? await auth.authenticate(request: &request)

        // Next request should fail with missingToken (empty state)
        var request2 = URLRequest(url: URL(string: "https://test.com")!)

        do {
            try await auth.authenticate(request: &request2)
            Issue.record("Should have thrown")
        } catch let error as AuthError {
            #expect(error == .missingToken)
        } catch {
            Issue.record("Wrong error type")
        }
    }
}

// MARK: - Custom Apply Tests

@Suite("TokenAuth Custom Apply")
struct TokenAuthCustomApplyTests {

    @Test("custom apply closure is used")
    func customApplyUsed() async throws {
        let auth = TokenAuth(
            name: "Test",
            refresh: { return .init(value: "token", expiresIn: 3600) },
            apply: { token, request in
                request.addValue("CustomScheme \(token.value)", forHTTPHeaderField: "X-Auth")
            }
        )

        await auth.set(token: .init(value: "custom_token", expiresIn: 3600))

        var request = URLRequest(url: URL(string: "https://test.com")!)
        try await auth.authenticate(request: &request)

        #expect(request.value(forHTTPHeaderField: "X-Auth") == "CustomScheme custom_token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("default apply uses Bearer scheme")
    func defaultApplyUsesBearer() async throws {
        let auth = TokenAuth(name: "Test") {
            return .init(value: "token", expiresIn: 3600)
        }

        await auth.set(token: .init(value: "jwt_token", expiresIn: 3600))

        var request = URLRequest(url: URL(string: "https://test.com")!)
        try await auth.authenticate(request: &request)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt_token")
    }
}

// MARK: - Error Handling Tests

@Suite("TokenAuth Error Handling")
struct TokenAuthErrorHandlingTests {

    @Test("state becomes invalid after generic refresh error")
    func stateBecomesInvalidAfterError() async throws {
        let refreshCount = AtomicCounter()

        let auth = TokenAuth(name: "Test") {
            let count = await refreshCount.increment()
            if count == 1 {
                throw NSError(domain: "Test", code: 1)
            }
            return .init(value: "recovered", expiresIn: 3600)
        }

        await auth.set(token: .init(value: "expired", expiration: Date.now.addingTimeInterval(-1)))

        // First attempt fails
        var request1 = URLRequest(url: URL(string: "https://test.com")!)
        do {
            try await auth.authenticate(request: &request1)
            Issue.record("Should have thrown")
        } catch {
            // Expected
        }

        // Second attempt should retry (state is invalid, not empty)
        var request2 = URLRequest(url: URL(string: "https://test.com")!)
        try await auth.authenticate(request: &request2)

        #expect(request2.value(forHTTPHeaderField: "Authorization") == "Bearer recovered")
        #expect(await refreshCount.value == 2)
    }
}

// MARK: - Wait State Tests

@Suite("TokenAuth Wait State")
struct TokenAuthWaitStateTests {

    @Test("multiple waiters are all resumed when token set")
    func multipleWaitersResumed() async throws {
        let auth = TokenAuth(name: "Test") {
            throw AuthError.failedToRefreshToken
        }

        // Start multiple waiting tasks
        let tasks = (0..<5).map { i in
            Task {
                var request = URLRequest(url: URL(string: "https://test.com/\(i)")!)
                try await auth.authenticate(request: &request)
                return request
            }
        }

        // Let them all start waiting
        try await Task.sleep(for: .milliseconds(50))

        // Set token - should unblock all
        await auth.set(token: .init(value: "shared_token", expiresIn: 3600))

        // All should complete with the same token
        for task in tasks {
            let request = try await task.value
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer shared_token")
        }
    }

    @Test("clear unblocks waiters with error")
    func clearUnblocksWaiters() async throws {
        let auth = TokenAuth(name: "Test") {
            throw AuthError.failedToRefreshToken
        }

        let task = Task {
            var request = URLRequest(url: URL(string: "https://test.com")!)
            try await auth.authenticate(request: &request)
        }

        try await Task.sleep(for: .milliseconds(50))

        await auth.clear()

        do {
            try await task.value
            Issue.record("Should have thrown")
        } catch let error as AuthError {
            #expect(error == .missingToken)
        } catch {
            // Could also be cancelled
        }
    }
}

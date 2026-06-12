//
//  AuthEngineTests.swift
//  NetworkActorTests
//

import Testing
import Foundation
@testable import NetworkActor

private func makeEngine(
    refreshDelay: Duration = .milliseconds(100),
    refreshResult: Result<TestToken, AuthError> = .success(.valid)
) -> AuthEngine<TestToken> {
    AuthEngine {
        try await Task.sleep(for: refreshDelay)
        switch refreshResult {
        case .success(let token): return token
        case .failure(let error): throw error
        }
    }
}

@Suite("AuthEngine State Machine")
struct AuthEngineTests {

    // Caso 1: .loading → set(validToken) → todas las waiters reciben ese token
    @Test("Case 1: loading → set(valid) → waiters get the token")
    func case1_loadingSetValidToken() async throws {
        let engine = makeEngine()
        let count = 20

        let tokens = try await withThrowingTaskGroup(of: TestToken.self) { group in
            for _ in 0..<count { group.addTask { try await engine.resolveToken() } }
            try await Task.sleep(for: .milliseconds(50))
            await engine.set(token: .valid)
            return try await group.reduce(into: [TestToken]()) { $0.append($1) }
        }

        #expect(tokens.count == count)
        #expect(tokens.allSatisfy { $0.id == TestToken.valid.id })
    }

    // Caso 2: .loading → set(expiredToken) → refresh se llama y los waiters reciben el nuevo token
    @Test("Case 2: loading → set(expired) → refresh called once, waiters get new token")
    func case2_loadingSetExpiredToken() async throws {
        let refreshed = TestToken(id: "refreshed-token", isValid: true)
        let engine = AuthEngine<TestToken> {
            try await Task.sleep(for: .milliseconds(50))
            return refreshed
        }
        let count = 20

        let tokens = try await withThrowingTaskGroup(of: TestToken.self) { group in
            for _ in 0..<count { group.addTask { try await engine.resolveToken() } }
            try await Task.sleep(for: .milliseconds(30))
            await engine.set(token: .expired)
            return try await group.reduce(into: [TestToken]()) { $0.append($1) }
        }

        #expect(tokens.count == count)
        #expect(tokens.allSatisfy { $0.id == refreshed.id })
    }

    // Caso 3: .ready(valid) → resolveToken() devuelve el mismo token sin llamar onRefresh
    @Test("Case 3: ready(valid) → resolveToken returns cached token without refresh")
    func case3_readyValidToken() async throws {
        let counter = Counter()
        let engine = AuthEngine<TestToken> {
            await counter.increment()
            return TestToken(id: "should-not-be-called", isValid: true)
        }
        await engine.set(token: .valid)

        let token = try await engine.resolveToken()

        #expect(token.id == TestToken.valid.id)
        #expect(await counter.value == 0)
    }

    // Caso 4: .ready(expired) → N llamadas concurrentes → onRefresh se llama exactamente 1 vez
    @Test("Case 4: ready(expired) → N concurrent calls → onRefresh called exactly once")
    func case4_concurrentRefreshCoalesced() async throws {
        let refreshed = TestToken(id: "refreshed", isValid: true)
        let counter = Counter()
        let engine = AuthEngine<TestToken> {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(100))
            return refreshed
        }
        await engine.set(token: .expired)

        let count = 50
        let tokens = try await withThrowingTaskGroup(of: TestToken.self) { group in
            for _ in 0..<count { group.addTask { try await engine.resolveToken() } }
            return try await group.reduce(into: [TestToken]()) { $0.append($1) }
        }

        #expect(tokens.count == count)
        #expect(tokens.allSatisfy { $0.id == refreshed.id })
        #expect(await counter.value == 1)
    }

    // Caso 5: .invalid → N llamadas concurrentes → onRefresh se llama exactamente 1 vez
    @Test("Case 5: invalid → N concurrent calls → onRefresh called exactly once")
    func case5_invalidConcurrentRefresh() async throws {
        let refreshed = TestToken(id: "refreshed", isValid: true)
        let counter = Counter()
        let engine = AuthEngine<TestToken> {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(100))
            return refreshed
        }
        await engine.set(token: .valid)
        await engine.invalidate()

        let count = 50
        let tokens = try await withThrowingTaskGroup(of: TestToken.self) { group in
            for _ in 0..<count { group.addTask { try await engine.resolveToken() } }
            return try await group.reduce(into: [TestToken]()) { $0.append($1) }
        }

        #expect(tokens.count == count)
        #expect(tokens.allSatisfy { $0.id == refreshed.id })
        #expect(await counter.value == 1)
    }

    // Caso 6: refresh() falla con invalidCredentials → estado queda .empty → siguiente llamada lanza .missingToken
    @Test("Case 6: refresh invalidCredentials → state becomes empty → next call throws missingToken")
    func case6_refreshInvalidCredentials() async throws {
        let engine = makeEngine(refreshResult: .failure(.invalidCredentials))
        await engine.set(token: .expired)

        await #expect(throws: AuthError.invalidCredentials) {
            try await engine.resolveToken()
        }
        await #expect(throws: AuthError.missingToken) {
            try await engine.resolveToken()
        }
    }

    // Caso 7: refresh() falla con error genérico → estado sigue .invalid → siguiente llamada reintenta refresh
    @Test("Case 7: refresh generic error → state stays invalid → next call retries refresh")
    func case7_refreshGenericError() async throws {
        let counter = Counter()
        let engine = AuthEngine<TestToken> {
            await counter.increment()
            throw AuthError.failedToRefreshToken
        }
        await engine.set(token: .expired)

        await #expect(throws: AuthError.failedToRefreshToken) {
            try await engine.resolveToken()
        }
        await #expect(throws: AuthError.failedToRefreshToken) {
            try await engine.resolveToken()
        }

        #expect(await counter.value == 2)
    }

    // Caso 8: clear() durante refresh en curso → awaiters reciben .cancelled
    @Test("Case 8: clear() during refresh → awaiters get .cancelled")
    func case8_clearDuringRefresh() async throws {
        let engine = AuthEngine<TestToken> {
            try await Task.sleep(for: .seconds(10))
            return .valid
        }
        await engine.set(token: .expired)

        let count = 20
        let errors = try await withThrowingTaskGroup(of: AuthError?.self) { group in
            for _ in 0..<count {
                group.addTask {
                    do {
                        _ = try await engine.resolveToken()
                        return nil
                    } catch let error as AuthError {
                        return error
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(50))
            await engine.clear()
            return try await group.reduce(into: [AuthError]()) { if let e = $1 { $0.append(e) } }
        }

        #expect(errors.count == count)
        #expect(errors.allSatisfy { $0 == .cancelled })
    }

    // Caso 9: .loading → clear() sin set(token) → waiters reciben .cancelled sin quedarse colgados
    @Test("Case 9: loading → clear() without set → waiters get .cancelled without hanging")
    func case9_clearWhileLoading() async throws {
        let engine = makeEngine()
        let count = 20

        let errors = try await withThrowingTaskGroup(of: AuthError?.self) { group in
            for _ in 0..<count {
                group.addTask {
                    do {
                        _ = try await engine.resolveToken()
                        return nil
                    } catch let error as AuthError {
                        return error
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(50))
            await engine.clear()
            return try await group.reduce(into: [AuthError]()) { if let e = $1 { $0.append(e) } }
        }

        #expect(errors.count == count)
        #expect(errors.allSatisfy { $0 == .cancelled })
    }
}

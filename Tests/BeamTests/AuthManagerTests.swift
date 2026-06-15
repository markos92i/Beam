//
//  AuthManagerTests.swift
//  NetworkActorTests
//

import Testing
import Foundation
import Beam

@Suite("AuthManager (legacy concurrency stress)")
struct AuthManagerTests {

    @Test("100 concurrent requests while loading → all get the set token")
    func testValidTokenRecovery() async throws {
        let manager = AuthManagerStub()
        let expectedTokenId = "valid-token-1234"
        let totalRequests = 100

        let tokens = try await withThrowingTaskGroup(of: TestToken.self) { group in
            for _ in 0..<totalRequests {
                group.addTask { try await manager.token }
            }
            try await Task.sleep(for: .milliseconds(500))
            await manager.set(token: TestToken(id: expectedTokenId, isValid: true))
            return try await group.reduce(into: [TestToken]()) { $0.append($1) }
        }

        #expect(tokens.count == totalRequests)
        #expect(tokens.allSatisfy { $0.id == expectedTokenId })
    }

    @Test("100 concurrent requests with expired token → all get the refreshed token")
    func testInvalidTokenRecovery() async throws {
        let manager = AuthManagerStub()
        let totalRequests = 100

        let tokens = try await withThrowingTaskGroup(of: TestToken.self) { group in
            for _ in 0..<totalRequests {
                group.addTask { try await manager.token }
            }
            try await Task.sleep(for: .milliseconds(500))
            await manager.set(token: TestToken(id: "old-token", isValid: false))
            return try await group.reduce(into: [TestToken]()) { $0.append($1) }
        }

        #expect(tokens.count == totalRequests)
        #expect(tokens.allSatisfy { $0.id == "new-token" })
    }
}

actor AuthManagerStub: AuthProtocol {
    typealias Token = TestToken

    static let shared = AuthManagerStub()

    private lazy var engine = AuthEngine<TestToken>(onRefresh: Self.refresh)

    var authHeader: [String: String] { get async throws { ["Authorization": "Bearer \(try await token.id)"] } }
    var token: TestToken { get async throws { try await engine.resolveToken() } }

    func set(token: TestToken) async { await engine.set(token: token) }
    func invalidate() async { await engine.invalidate() }
    func clear() async { await engine.clear() }

    static func refresh() async throws -> TestToken {
        try await Task.sleep(for: .seconds(2))
        return TestToken(id: "new-token", isValid: true)
    }
}

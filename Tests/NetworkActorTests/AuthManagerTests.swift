//
//  AuthManagerTests.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 13/05/2026.
//  Copyright © 2026 SNGULAR. All rights reserved.
//

import Testing
import Foundation
import NetworkActor

struct AuthManagerTests {
    @Test("Test concurrent token requests with a simulated keychain access delay")
    func testValidTokenRecovery() async throws {
        let manager = AuthManagerStub()
        let expectedTokenId = "valid-token-1234"
        let totalRequests = 100
           
        var results: [TokenStub] = []

        try await withThrowingTaskGroup(of: TokenStub.self) { group in
            for _ in 0..<totalRequests {
                group.addTask { try await manager.token }
            }

            try await Task.sleep(for: .milliseconds(500))

            let initialToken = TokenStub(id: expectedTokenId, date: .now, expiration: TimeInterval(3600))
            await manager.set(token: initialToken)
            
            for try await token in group {
                results.append(token)
            }
        }
        
        #expect(results.count == totalRequests)
        
        for token in results {
            #expect(token.id == expectedTokenId)
        }
    }
    
    @Test("Test concurrent token requests")
    func testInvalidTokenRecovery() async throws {
        let manager = AuthManagerStub()
        let expectedTokenId = "new-token"
        let totalRequests = 100
           
        var results: [TokenStub] = []

        try await withThrowingTaskGroup(of: TokenStub.self) { group in
            for _ in 0..<totalRequests {
                group.addTask { try await manager.token }
            }

            try await Task.sleep(for: .milliseconds(500))

            let initialToken = TokenStub(id: "old-token", date: .distantPast, expiration: TimeInterval(3600))
            await manager.set(token: initialToken)
            
            for try await token in group {
                results.append(token)
            }
        }
        
        #expect(results.count == totalRequests)
        
        for token in results {
            #expect(token.id == expectedTokenId)
        }
    }
}

struct TokenStub {
    var id: String
    var date: Date
    var expiration: TimeInterval
}

extension TokenStub: AuthToken {
    public var isValid: Bool { Date.now < date.addingTimeInterval(expiration) }
}

actor AuthManagerStub: AuthProtocol {
    static let shared = AuthManagerStub()
    
    private lazy var engine = AuthEngine(onRefresh: Self.refresh)
    
    var authHeader: [String: String] { get async throws { ["Authorization": "Bearer \(try await token.id)"] } }
    var token: TokenStub { get async throws { try await engine.resolveToken() } }
        
    func set(token: TokenStub) async { await engine.set(token: token) }
    
    func invalidate() async { await engine.invalidate() }

    func clear() async { await engine.clear() }
            
    static func refresh() async throws -> TokenStub {
        try await Task.sleep(for: .milliseconds(1500))

        return Token(id: "new-token", date: .now, expiration: 3600)
    }
}

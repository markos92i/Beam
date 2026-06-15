//
//  AuthTestHelpers.swift
//  NetworkActorTests
//

import Foundation
import Beam

struct TestToken: AuthToken, Sendable {
    let id: String
    let isValid: Bool

    static let valid = TestToken(id: "valid-token", isValid: true)
    static let expired = TestToken(id: "expired-token", isValid: false)
}

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

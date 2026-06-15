//
//  AuthProtocol.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

public protocol AuthToken: Sendable {
    var isValid: Bool { get }
}

public protocol AuthProtocol: Sendable {
    associatedtype Token: AuthToken
    
    var authHeader: [String: String] { get async throws }
    var token: Token { get async throws }
    
    func set(token: Token) async
    func invalidate() async
    func clear() async
}

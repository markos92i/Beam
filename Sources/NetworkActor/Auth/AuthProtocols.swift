//
//  AuthProtocol.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import Foundation

public protocol AuthToken: Sendable {
    var isValid: Bool { get }
}

public protocol AuthProtocol: Sendable {
    associatedtype Token: AuthToken
    
    var authHeader: [String: String] { get async throws }
    var token: Token { get async throws }
    
    func restore(token: Token) async
    func clear() async
}

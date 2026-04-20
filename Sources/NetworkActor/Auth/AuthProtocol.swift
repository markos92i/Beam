//
//  AuthProtocol.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import SwiftUI

public protocol AuthProtocol: Sendable {
    var authHeader: [String: String] { get async throws }
    var token: Token { get async throws }
    func restore(token: Token) async
    func clear() async
}

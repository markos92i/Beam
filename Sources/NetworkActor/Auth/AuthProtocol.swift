//
//  AuthProtocol.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import SwiftUI

public protocol AuthProtocol: Sendable {
    var authHeader: [String: String] { get async throws }
    var token: Token { get async throws }
    func restore(token: Token) async
    func clear() async
}

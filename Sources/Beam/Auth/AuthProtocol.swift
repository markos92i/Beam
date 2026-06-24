//
//  AuthProtocol.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

/// Contract for authentication providers used by Endpoint.
public protocol AuthProtocol: Sendable {
    /// Applies authentication to the outgoing request.
    ///
    /// Implementations should add headers, query parameters, or any other
    /// authentication artifact directly to the request.
    func authenticate(request: inout URLRequest) async throws

    /// Marks the current authentication state as invalid, triggering
    /// refresh on next access.
    func invalidate() async
}

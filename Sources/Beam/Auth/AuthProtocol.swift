//
//  AuthProtocol.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

/// An authentication provider. Beam's providers log with the level of `LogSubsystem.beam`, not `@API(logLevel:)`.
public protocol AuthProtocol: Sendable {
    /// Adds credentials to the outgoing request.
    func authenticate(request: inout URLRequest) async throws(AuthError)

    /// Marks the credentials invalid, so the next access refreshes them.
    func invalidate() async
}

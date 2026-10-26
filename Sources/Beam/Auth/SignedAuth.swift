//
//  SignedAuth.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 16/06/2026.
//

import Foundation

/// Auth provider for HMAC or signature-based authentication.
public actor SignedAuth: AuthProtocol {

    private let name: String
    private let sign: @Sendable (inout URLRequest) async throws(AuthError) -> Void
    private let log = BeamLogger()

    /// `name` identifies the provider in logs. `apply` signs the request, or throws (e.g. `.missingToken`).
    public init(name: String = "Signed", apply: @escaping @Sendable (inout URLRequest) async throws(AuthError) -> Void) {
        self.name = name
        self.sign = apply
    }

    // MARK: - AuthProtocol

    public func authenticate(request: inout URLRequest) async throws(AuthError) {
        try await sign(&request)
    }

    public func invalidate() async {
        // Signed credentials can't be refreshed; the provider stays usable.
        log.log(.auth(type: "SignedAuth", name: name, detail: "rejected", level: .debug))
    }
}

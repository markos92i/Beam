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
    private let sign: @Sendable (inout URLRequest) async throws -> Void
    private let log = BeamLogger()

    /// Creates a signature-based auth provider.
    ///
    /// - Parameters:
    ///   - name: Identifier for this auth provider (used in logs).
    ///   - apply: Closure that mutates the URLRequest to add credentials and signature.
    public init(name: String = "Signed", apply: @escaping @Sendable (inout URLRequest) async throws -> Void) {
        self.name = name
        self.sign = apply
    }

    // MARK: - AuthProtocol

    public func authenticate(request: inout URLRequest) async throws {
        try await sign(&request)
    }

    public func invalidate() async {
        // No-op: signed credentials cannot be refreshed. Individual requests
        // will fail with 401 if the signature is rejected, but the provider
        // remains usable for subsequent calls.
        log.log(.auth(type: "SignedAuth", name: name, detail: "rejected"))
    }
}

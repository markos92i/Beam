//
//  StaticAuth.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 16/06/2026.
//

import Foundation

/// Auth provider for static credentials that never expire (API keys, fixed tokens).
public actor StaticAuth: AuthProtocol {

    private let name: String
    private let apply: @Sendable (inout URLRequest) -> Void
    private let log = BeamLogger()

    /// Creates a static auth provider.
    ///
    /// - Parameters:
    ///   - name: Identifier for this auth provider (used in logs).
    ///   - apply: Closure that adds static credentials to the request.
    public init(name: String = "Static", apply: @escaping @Sendable (inout URLRequest) -> Void) {
        self.name = name
        self.apply = apply
    }

    // MARK: - AuthProtocol

    public func authenticate(request: inout URLRequest) async throws {
        apply(&request)
    }

    public func invalidate() async {
        // No-op: static credentials cannot be refreshed. Individual requests
        // will fail with 401 if the key is rejected, but the provider
        // remains usable for subsequent calls.
        log.log(.auth(type: "StaticAuth", name: name, detail: "rejected"))
    }
}

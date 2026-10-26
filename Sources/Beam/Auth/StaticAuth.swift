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

    /// `name` identifies the provider in logs. `apply` adds the credentials to the request.
    public init(name: String = "Static", apply: @escaping @Sendable (inout URLRequest) -> Void) {
        self.name = name
        self.apply = apply
    }

    // MARK: - AuthProtocol

    public func authenticate(request: inout URLRequest) async {
        apply(&request)
    }

    public func invalidate() async {
        // Static credentials can't be refreshed; the provider stays usable.
        log.log(.auth(type: "StaticAuth", name: name, detail: "rejected", level: .debug))
    }
}

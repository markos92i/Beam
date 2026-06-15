//
//  AuthPolicy.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

/// Defines how authentication errors are handled for a request.
public enum AuthPolicy: Sendable, Equatable {
    /// Auth is required. If the auth provider fails, the request fails.
    case required

    /// Auth is optional. If the auth provider fails (no token, expired session),
    /// the request proceeds without the auth header.
    case optional
}

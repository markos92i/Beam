//
//  AuthPolicy.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

/// What a request does when its auth provider fails.
public enum AuthPolicy: Sendable, Equatable {
    /// The request fails.
    case required

    /// The request proceeds without the auth header.
    case optional
}

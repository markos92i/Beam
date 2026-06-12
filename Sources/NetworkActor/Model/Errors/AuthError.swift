//
//  AuthError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 30/3/25.
//

import Foundation

public enum AuthError: Error, InfoError, Sendable, Equatable {
    case missingToken
    case invalidCredentials
    case failedToRefreshToken
    case cancelled

    var info: [String: any Sendable] {
        switch self {
        case .missingToken:
            ["AuthError": "No token available — user may not be logged in"]
        case .invalidCredentials:
            ["AuthError": "Credentials rejected by server"]
        case .failedToRefreshToken:
            ["AuthError": "Token refresh failed — session expired"]
        case .cancelled:
            ["AuthError": "Authentication cancelled"]
        }
    }
}

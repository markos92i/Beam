//
//  AuthError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 30/3/25.
//

import Foundation

public enum AuthError: Error, LoggableError, Sendable, Equatable {
    case missingToken
    case invalidCredentials
    case failedToRefreshToken
    case cancelled

    var logDescription: String {
        switch self {
        case .missingToken:
            "No token available — user may not be logged in"
        case .invalidCredentials:
            "Credentials rejected by server"
        case .failedToRefreshToken:
            "Token refresh failed — session expired"
        case .cancelled:
            "Authentication cancelled"
        }
    }
}

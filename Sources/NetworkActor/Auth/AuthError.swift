//
//  AuthError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation

public enum AuthError: Error, Sendable {
    case missingToken
    case invalidCredentials
    case failedToRefreshToken
}

//
//  AuthError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 30/3/25.
//

import Foundation

public enum AuthError: Error, Sendable {
    case missingToken
    case invalidCredentials
    case failedToRefreshToken
}

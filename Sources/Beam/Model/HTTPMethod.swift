//
//  HTTPMethod.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 5/1/25.
//

import Foundation

public enum HTTPMethod: String, Sendable, CustomStringConvertible {
    case delete = "DELETE"
    case get = "GET"
    case head = "HEAD"
    case options = "OPTIONS"
    case patch = "PATCH"
    case post = "POST"
    case put = "PUT"
    case trace = "TRACE"
    
    public var description: String { rawValue }

    /// RFC 9110 §9.2.2: sending it twice has the same effect as once.
    var isIdempotent: Bool {
        switch self {
        case .get, .head, .options, .trace, .put, .delete: true
        case .post, .patch: false
        }
    }
}

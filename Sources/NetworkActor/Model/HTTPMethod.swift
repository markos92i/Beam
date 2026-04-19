//
//  HTTPMethod.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 5/1/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import Foundation

public enum HTTPMethod: String, Sendable, CustomStringConvertible {
    case connect = "CONNECT"
    case delete = "DELETE"
    case get = "GET"
    case head = "HEAD"
    case options = "OPTIONS"
    case patch = "PATCH"
    case post = "POST"
    case put = "PUT"
    case trace = "TRACE"
    
    public var description: String { rawValue }
}

//
//  SerializerError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

public enum SerializerError: Error {
    case encoding(Error, info: [String: any Sendable])
    case decoding(Error, info: [String: any Sendable])
    
    init(encodingError: EncodingError) {
        var info: [String: String] = [:]
        
        switch encodingError {
        case .invalidValue(let value, let context):
            info["EncodingError"] = "invalidValue(value: \(value), path: \(context.formattedPath))"
        @unknown default:
            info["EncodingError"] = "unknown"
        }
        
        self = .encoding(encodingError, info: info)
    }
    
    init(decodingError: DecodingError) {
        var info: [String: String] = [:]
        
        switch decodingError {
        case .typeMismatch(let type, let context):
            info["DecodingError"] = "typeMismatch(type: \(type), path: \(context.formattedPath), description: \(context.debugDescription))"
        case .valueNotFound(let type, let context):
            info["DecodingError"] = "valueNotFound(type: \(type), path: \(context.formattedPath), description: \(context.debugDescription))"
        case .keyNotFound(let key, let context):
            info["DecodingError"] = "keyNotFound(key: \"\(key.stringValue)\", path: \(context.formattedPath), description: \(context.debugDescription))"
        case .dataCorrupted(let context):
            info["DecodingError"] = "dataCorrupted(path: \(context.formattedPath), description: \(context.debugDescription))"
        @unknown default:
            info["DecodingError"] = "unknown"
        }
        
        self = .decoding(decodingError, info: info)
    }
}

private extension DecodingError.Context {
    var formattedPath: String {
        codingPath.compactMap { $0.stringValue }.joined(separator: ".")
    }
}

private extension EncodingError.Context {
    var formattedPath: String {
        codingPath.compactMap { $0.stringValue }.joined(separator: ".")
    }
}

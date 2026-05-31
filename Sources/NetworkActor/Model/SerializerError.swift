//
//  SerializerError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

public enum SerializerError: Error {
    case unsuported
    case incorrect
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

extension SerializerError {
    var info: [String: any Sendable] {
        switch self {
        case .unsuported: ["Unsupported": "The inferred type is not supported by the serializer, try using a different one, implement your own serializer that supports it, or contact the developer to add support for this type"]
        case .incorrect: ["Incorrect": "The inferred type does not match the type of the value"]
        case .encoding(_, info: let info): info
        case .decoding(_, info: let info): info
        }
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

//
//  MapperError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

public enum MapperError: Error, LoggableError {
    case unsuported
    case incorrect
    case encoding(Error, description: String)
    case decoding(Error, description: String)
    
    init(encodingError: EncodingError) {
        let description: String = switch encodingError {
        case .invalidValue(let value, let context):
            context.formattedTree(error: "invalidValue", detail: "\(type(of: value)) 􀰌 􀃰 could not encode")
        @unknown default:
            "unknown"
        }
        
        self = .encoding(encodingError, description: description)
    }
    
    init(decodingError: DecodingError) {
        let description: String = switch decodingError {
        case .typeMismatch(let type, let context):
            context.formattedTree(error: "typeMismatch", detail: "\(type) 􀰌 􀃰 wrong type")
        case .valueNotFound(let type, let context):
            context.formattedTree(error: "valueNotFound", detail: "\(type) 􀰌 􀃰 nil value")
        case .keyNotFound(let key, let context):
            context.formattedTree(error: "keyNotFound", detail: "\"\(key.stringValue)\" 􀃰 missing key")
        case .dataCorrupted(let context):
            context.formattedTree(error: "dataCorrupted", detail: "􀃰 \(context.debugDescription)")
        @unknown default:
            "unknown"
        }
        
        self = .decoding(decodingError, description: description)
    }

    var logDescription: String {
        switch self {
        case .unsuported:
            "The mapper does not support this type. Use a custom Mapper or change the response type."
        case .incorrect:
            "The response type does not match the data received from the server."
        case .encoding(_, let description):
            description
        case .decoding(_, let description):
            description
        }
    }
}

// MARK: - Coding Path Formatting

/// Renders a coding path as an indented tree for structured error logging.
private func formattedTree(codingPath: [CodingKey], error: String, detail: String) -> String {
    let indent = "    "
    var lines = [error]
    var segments: [String] = []

    for key in codingPath {
        if let index = key.intValue {
            if let last = segments.last {
                segments[segments.count - 1] = "\(last)[\(index)]"
            } else {
                segments.append("[\(index)]")
            }
        } else {
            segments.append(key.stringValue)
        }
    }

    for (i, segment) in segments.enumerated() {
        let prefix = String(repeating: indent, count: i + 1)
        if i == segments.count - 1 {
            lines.append("\(prefix)\(segment): \(detail)")
        } else {
            lines.append("\(prefix)\(segment):")
        }
    }

    return lines.joined(separator: "\n")
}

private extension DecodingError.Context {
    func formattedTree(error: String, detail: String) -> String {
        Beam.formattedTree(codingPath: codingPath, error: error, detail: detail)
    }
}

private extension EncodingError.Context {
    func formattedTree(error: String, detail: String) -> String {
        Beam.formattedTree(codingPath: codingPath, error: error, detail: detail)
    }
}

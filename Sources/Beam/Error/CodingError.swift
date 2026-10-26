//
//  CodingError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

/// Failures of encoding or decoding a body.
public enum CodingError: Error, LoggableError {
    /// The body isn't of the form the call reads: not UTF-8 text, not an image, or replaced by an interceptor.
    case typeMismatch
    /// `description` renders the coding path.
    case encoding(EncodingError, description: String)
    /// `description` renders the coding path.
    case decoding(DecodingError, description: String)
    
    init(encodingError: EncodingError) {
        let description: String = switch encodingError {
        case .invalidValue(let value, let context):
            formattedTree(codingPath: context.codingPath, error: "invalidValue", detail: "\(type(of: value)) 􀰌 􀃰 could not encode")
        @unknown default:
            "unknown"
        }
        
        self = .encoding(encodingError, description: description)
    }
    
    init(decodingError: DecodingError) {
        let description: String = switch decodingError {
        case .typeMismatch(let type, let context):
            formattedTree(codingPath: context.codingPath, error: "typeMismatch", detail: "\(type) 􀰌 􀃰 wrong type")
        case .valueNotFound(let type, let context):
            formattedTree(codingPath: context.codingPath, error: "valueNotFound", detail: "\(type) 􀰌 􀃰 nil value")
        case .keyNotFound(let key, let context):
            formattedTree(codingPath: context.codingPath, error: "keyNotFound", detail: "\"\(key.stringValue)\" 􀃰 missing key")
        case .dataCorrupted(let context):
            formattedTree(codingPath: context.codingPath, error: "dataCorrupted", detail: "􀃰 \(context.debugDescription)")
        @unknown default:
            "unknown"
        }
        
        self = .decoding(decodingError, description: description)
    }

    @inline(always)
    var logDescription: String {
        switch self {
        case .typeMismatch:
            "The body doesn't have the expected form (text, image, data or a file)."
        case .encoding(_, let description), .decoding(_, let description):
            description
        }
    }
}

// MARK: - Coding Path Formatting

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

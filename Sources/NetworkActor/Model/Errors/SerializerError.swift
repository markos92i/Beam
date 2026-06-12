//
//  SerializerError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

public enum SerializerError: Error, InfoError {
    case unsuported
    case incorrect
    case encoding(Error, info: [String: any Sendable])
    case decoding(Error, info: [String: any Sendable])
    
    init(encodingError: EncodingError) {
        var info: [String: String] = [:]
        
        switch encodingError {
        case .invalidValue(let value, let context):
            info["EncodingError"] = context.formattedTree(error: "invalidValue", detail: "\(type(of: value)) 􀰌 􀃰 could not encode")
        @unknown default:
            info["EncodingError"] = "unknown"
        }
        
        self = .encoding(encodingError, info: info)
    }
    
    init(decodingError: DecodingError) {
        var info: [String: String] = [:]
        
        switch decodingError {
        case .typeMismatch(let type, let context):
            info["DecodingError"] = context.formattedTree(error: "typeMismatch", detail: "\(type) 􀰌 􀃰 wrong type")
        case .valueNotFound(let type, let context):
            info["DecodingError"] = context.formattedTree(error: "valueNotFound", detail: "\(type) 􀰌 􀃰 nil value")
        case .keyNotFound(let key, let context):
            info["DecodingError"] = context.formattedTree(error: "keyNotFound", detail: "\"\(key.stringValue)\" 􀃰 missing key")
        case .dataCorrupted(let context):
            info["DecodingError"] = context.formattedTree(error: "dataCorrupted", detail: context.debugDescription)
        @unknown default:
            info["DecodingError"] = "unknown"
        }
        
        self = .decoding(decodingError, info: info)
    }
}

extension SerializerError {
    var info: [String: any Sendable] {
        switch self {
        case .unsuported: ["DecodingError": "\n    The serializer does not support this type. Use a custom Serializer or change the response type."]
        case .incorrect: ["DecodingError": "\n    The response type does not match the data received from the server."]
        case .encoding(_, info: let info): info
        case .decoding(_, info: let info): info
        }
    }

    var logLines: (subtitle: String?, detail: [String]) {
        let raw: String? = switch self {
        case .unsuported: info["DecodingError"] as? String
        case .incorrect: info["DecodingError"] as? String
        case .encoding(_, let info): info["EncodingError"] as? String
        case .decoding(_, let info): info["DecodingError"] as? String
        }
        guard let raw else { return (nil, []) }
        let lines = raw.split(separator: "\n").map(String.init)
        guard let first = lines.first else { return (nil, []) }
        var detail = Array(lines.dropFirst())
        if !detail.isEmpty { detail[0] = "􀺾 \(detail[0].trimmingCharacters(in: .whitespaces))" }
        return (first, detail)
    }
}

private extension DecodingError.Context {
    var formattedPath: String {
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                if !result.isEmpty { result += "." }
                result += key.stringValue
            }
        }
        return result
    }

    func formattedTree(error: String, detail: String) -> String {
        let indent = "    "
        var lines = [error]
        var segments: [String] = []

        // Build segments merging array indices with previous key
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

        // Print tree with last segment including detail
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
}

private extension EncodingError.Context {
    func formattedTree(error: String, detail: String) -> String {
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
}


//
//  MacroError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation
import SwiftDiagnostics

struct MacroError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

// MARK: - Diagnostics

enum MacroDiagnostic: DiagnosticMessage {
    case invalidPathCharacters(path: String)
    case pathMustStartWithSlash(path: String)
    case pathNotLiteral
    case pathInterpolation
    case invalidPlaceholder(String)
    case queryNotLiteral
    case taskNotLiteral
    case socketBody
    case socketURL
    case contentNotAllowed(ContentlessMethod)
    case bodyWithFile
    case uploadWithoutContent
    case pingOutOfRange(String)
    case invalidMessageSize
    case unusedSocketConfig
    case unusedBackground

    var message: String {
        switch self {
        case .invalidPathCharacters(let path):
            "Route path '\(path)' contains invalid URL characters (spaces, <, >, |, \\, ^, `)"
        case .pathMustStartWithSlash(let path):
            "Route path '\(path)' must start with '/'"
        case .pathNotLiteral:
            "Route path must be a string literal; use {name} placeholders for dynamic values"
        case .pathInterpolation:
            "Route paths can't use string interpolation; write a {name} placeholder and provide it as a parameter or an APIValues property"
        case .invalidPlaceholder(let name):
            "'{\(name)}' is not a valid placeholder: the name must be a Swift identifier"
        case .queryNotLiteral:
            "Route 'query:' must be a dictionary literal of string literals; use \"{name}\" values for dynamic ones"
        case .taskNotLiteral:
            "Route 'task:' must be written as .data, .upload, .download or .bytes: the macro reads it at compile time"
        case .socketBody:
            "A WebSocket route can't have a body: the connection opens with a GET handshake; send data with send(_:) once connected"
        case .socketURL:
            "A WebSocket route connects to its API's host and path: 'url' is not an absolute target here; use another label for other values"
        case .contentNotAllowed(let method):
            "A \(method.name) route can't send a body or upload: \(method.reason). Send the values as query items, or use a method that carries content (POST, PUT, PATCH)"
        case .bodyWithFile:
            "An upload route uploads its body or its file, not both: one of them would be dropped. Declare one route with `body` and another with `url`"
        case .uploadWithoutContent:
            "An upload route needs something to upload: a `body` parameter or the `url` of a file"
        case .pingOutOfRange(let ping):
            "'ping: \(ping)' is out of range: URLSession pings between 1 and 300 seconds"
        case .invalidMessageSize:
            "'maxMessageSize' must be greater than zero"
        case .unusedSocketConfig:
            "'socket:' has no effect: this API has no @Socket routes"
        case .unusedBackground:
            "'background:' has no effect: this API has no upload or download routes"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "BeamMacros", id: String(String(describing: self).prefix { $0 != "(" }))
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .invalidPathCharacters, .pathMustStartWithSlash, .unusedSocketConfig, .unusedBackground: .warning
        default: .error
        }
    }
}

// MARK: - Methods without request content

/// No DELETE or OPTIONS: RFC 9110 allows content in them and URLSession sends it.
enum ContentlessMethod: String {
    case get, head, trace

    var name: String { rawValue.uppercased() }

    var reason: String {
        switch self {
        case .get:
            "content in a GET has no defined semantics (RFC 9110 §9.3.1); URLSession fails data, stream and upload tasks (URLError -1103) and drops it in downloads over HTTP/1.1"
        case .head:
            "content in a HEAD has no defined semantics (RFC 9110 §9.3.2); URLSession never sends it, and in data and upload tasks it still sends a Content-Length, so the server waits for bytes that never come"
        case .trace:
            "a client must not send content in a TRACE request (RFC 9110 §9.3.8)"
        }
    }
}

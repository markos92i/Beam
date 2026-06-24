//
//  MacroError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation
import SwiftDiagnostics

enum MacroError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let msg): msg
        }
    }
}

// MARK: - Diagnostics

enum MacroDiagnostic: DiagnosticMessage {
    case invalidPathCharacters(path: String)
    case pathMustStartWithSlash(path: String)

    var message: String {
        switch self {
        case .invalidPathCharacters(let path):
            "Route path '\(path)' contains invalid URL characters (spaces, <, >, |, \\, ^, `)"
        case .pathMustStartWithSlash(let path):
            "Route path '\(path)' must start with '/'"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .invalidPathCharacters:
            MessageID(domain: "BeamMacros", id: "invalidPathCharacters")
        case .pathMustStartWithSlash:
            MessageID(domain: "BeamMacros", id: "pathMustStartWithSlash")
        }
    }

    var severity: DiagnosticSeverity { .warning }
}

//
//  LogBuilder.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 25/06/2026.
//

import Foundation

// MARK: - LogBuilder

/// Result builder for declarative log line composition.
///
/// Supports strings, arrays of strings, optionals, and conditionals:
/// ```swift
/// build {
///     "header line"
///     if let headers, !headers.isEmpty {
///         formatHeaders(headers)
///     }
///     if config.verbose {
///         bodyLines
///     } else {
///         "compact summary"
///     }
/// }
/// ```
@resultBuilder
enum LogBuilder {
    static func buildBlock(_ components: [String]...) -> [String] { components.flatMap { $0 } }
    static func buildExpression(_ expression: String) -> [String] { [expression] }
    static func buildExpression(_ expression: [String]) -> [String] { expression }
    static func buildOptional(_ component: [String]?) -> [String] { component ?? [] }
    static func buildEither(first component: [String]) -> [String] { component }
    static func buildEither(second component: [String]) -> [String] { component }
    static func buildArray(_ components: [[String]]) -> [String] { components.flatMap { $0 } }
}

// MARK: - Build Helper

/// Builds log lines using the `@LogBuilder` DSL.
func build(@LogBuilder _ content: () -> [String]) -> [String] {
    content()
}

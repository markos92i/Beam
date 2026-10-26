//
//  LogBuilder.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 25/06/2026.
//

import Foundation

// MARK: - LogBuilder

/// Composes log lines from strings, string arrays, optionals and conditionals.
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

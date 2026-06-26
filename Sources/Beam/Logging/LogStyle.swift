//
//  LogStyle.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 25/06/2026.
//

import Foundation

// MARK: - LogStyle

/// Visual decoration applied to log lines before emission.
enum LogStyle: Sendable {
    /// No decoration — lines are emitted as-is.
    case none

    /// Prefixes each line with `│ `.
    case pipe

    /// Wraps lines in a closed box.
    case boxed
}

// MARK: - Styling

extension [String] {
    /// Applies the given style decoration to each line.
    func styled(_ style: LogStyle) -> [String] {
        let expanded = flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }

        switch style {
        case .none:
            return expanded

        case .pipe:
            return expanded.map { "│ \($0)" }

        case .boxed:
            let maxLen = expanded.map(\.count).max() ?? 0
            let bar = String(repeating: "─", count: maxLen + 2)
            return build {
                "╭\(bar)╮"
                expanded.map { "│ \($0.padding(toLength: maxLen, withPad: " ", startingAt: 0)) │" }
                "╰\(bar)╯"
            }
        }
    }
}

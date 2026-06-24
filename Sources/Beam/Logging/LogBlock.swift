//
//  LogBlock.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 17/06/2026.
//

import Foundation

// MARK: - LogBlock

/// Structured text block for log output.
struct LogBlock: Sendable {

    /// Visual style of the block.
    enum Style: Sendable {
        /// Prefixes each line with `│ `.
        case pipe

        /// Prefixes each line with `│ ` and adds empty lines before and after.
        case spaced

        /// Wraps lines in a `╭╰` box with an optional title.
        case boxed(title: String? = nil)
    }

    let lines: [String]
    let style: Style

    init(_ lines: [String], style: Style = .pipe) {
        self.lines = lines
        self.style = style
    }

    init(_ line: String, style: Style = .pipe) {
        self.lines = [line]
        self.style = style
    }

    // MARK: - Rendering

    /// Renders the final formatted string.
    func rendered() -> String {
        switch style {
        case .pipe:
            return lines.map { "│ \($0)" }.joined(separator: "\n")

        case .spaced:
            let body = lines.map { "│ \($0)" }
            return (["│"] + body + ["│"]).joined(separator: "\n")

        case .boxed(let title):
            let header = if let title {
                "│ ╭── \(title) ──"
            } else {
                "│ ╭──"
            }
            let body = lines.map { "│ │ \($0)" }
            let footer = "│ ╰──"
            return ([header] + body + [footer]).joined(separator: "\n")
        }
    }
}

// MARK: - Convenience builders

extension LogBlock {
    /// Simple pipe block (default logger style).
    static func pipe(_ lines: [String]) -> LogBlock {
        LogBlock(lines, style: .pipe)
    }

    /// Block with vertical spacing (for errors or highlighted blocks).
    static func spaced(_ lines: [String]) -> LogBlock {
        LogBlock(lines, style: .spaced)
    }

    /// Block wrapped in a visual box.
    static func boxed(_ lines: [String], title: String? = nil) -> LogBlock {
        LogBlock(lines, style: .boxed(title: title))
    }
}

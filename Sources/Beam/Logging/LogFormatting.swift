//
//  LogFormatting.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 17/06/2026.
//

import Foundation

// MARK: - Int

extension Int {
    var byteFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
            .replacingOccurrences(of: " ", with: "")
    }

    var statusIcon: String {
        switch self {
        case 200..<300: "􀁢"
        case 300..<400: "􀅴"
        default:        "􀁞"
        }
    }
}

// MARK: - Date

extension Date {
    var elapsed: String {
        Duration.seconds(-timeIntervalSinceNow).formatted
    }
}

// MARK: - Duration

extension Duration {
    var formatted: String {
        let raw = self.formatted(.units(
            allowed: [.hours, .minutes, .seconds, .milliseconds],
            width: .narrow,
            maximumUnitCount: 2,
            fractionalPart: .hide
        ))
        return raw.replacingOccurrences(of: #"(\d)\s+([\w])"#, with: "$1$2", options: .regularExpression)
    }
}

// MARK: - URL

extension URL {
    var protocolLabel: String {
        switch scheme {
        case "https", "wss": "􀎠 \(scheme!)"
        case "http", "ws": "􀎢 \(scheme!)"
        default: scheme ?? ""
        }
    }

    var hostLabel: String {
        "􀪯 \(host() ?? "")"
    }

    var pathLabel: String {
        "􀈕 \(path())"
    }

    var queryLabel: String? {
        query.map { "􀊫 \($0)" }
    }
}

// MARK: - Data

extension Data {
    var isJSON: Bool { first == 0x7B || first == 0x5B }

    var prettyJSON: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return String(data: self, encoding: .utf8)
        }
        return prettyString
    }

}

// MARK: - Columns

/// Aligns `\t`-separated columns so a request and its response line up.
enum LogColumns {
    static let widths = [7, 10, 9]
    static let gap = 4

    static func align(_ line: String) -> String {
        var columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        while columns.count > 1, columns.last?.isEmpty == true { columns.removeLast() }
        return columns.enumerated().map { index, column in
            guard index < columns.count - 1 else { return String(column) }
            let width = index < widths.count ? widths[index] : 0
            return column + String(repeating: " ", count: max(width - cells(column), 0) + gap)
        }.joined()
    }

    /// An SF Symbol (private use planes) takes about two monospaced console cells.
    private static func cells(_ text: Substring) -> Int {
        text.unicodeScalars.reduce(0) { $0 + ($1.value >= 0xF0000 ? 2 : 1) }
    }
}

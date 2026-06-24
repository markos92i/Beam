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
}

// MARK: - String

extension String {
    var byteFormatted: String { (Int(self) ?? 0).byteFormatted }
}

// MARK: - Date

extension Date {
    var elapsed: String {
        let raw = Duration.seconds(-timeIntervalSinceNow)
            .formatted(.units(
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
        "􀉣 \(host() ?? "")"
    }

    var pathAndQuery: String {
        var result = "􀈕 \(path())"
        if let query { result += "?\(query)" }
        return result
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

    func jsonLog(max: Int) -> [String] {
        let pretty = prettyJSON ?? String(data: self, encoding: .utf8) ?? "\(count) bytes"
        var lines = String(pretty.prefix(max)).split(separator: "\n").map(String.init)
        if pretty.count > max { lines.append("+ \(count.byteFormatted) total") }
        return lines
    }
}

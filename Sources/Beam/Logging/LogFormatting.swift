//
//  LogFormatting.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 17/06/2026.
//

import Foundation

// MARK: - Int

extension Int {
    var statusIcon: String {
        switch self {
        case 200..<300: "􀁢"
        case 300..<400: "􀅴"
        default:        "􀁞"
        }
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

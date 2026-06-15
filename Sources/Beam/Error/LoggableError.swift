//
//  LoggableError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/06/2026.
//

import Foundation

protocol LoggableError: Error {
    var info: [String: any Sendable] { get }
    var logLines: (subtitle: String?, detail: [String]) { get }
}

extension LoggableError {
    var logLines: (subtitle: String?, detail: [String]) {
        guard let value = info.values.first else { return (nil, []) }
        return (nil, ["􀺾 \(value)"])
    }
}

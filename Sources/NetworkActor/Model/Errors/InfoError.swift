//
//  InfoError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/06/2026.
//

import Foundation

protocol InfoError: Error {
    var info: [String: any Sendable] { get }
    var logLines: (subtitle: String?, detail: [String]) { get }
}

extension InfoError {
    var logLines: (subtitle: String?, detail: [String]) {
        guard let value = info.values.first else { return (nil, []) }
        return (nil, ["􀺾 \(value)"])
    }
}

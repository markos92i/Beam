//
//  FileError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

public enum FileError: Error, InfoError {
    case invalidTargetURL
    case removeFailed(Error)
    case copyFailed(Error)

    var info: [String: any Sendable] {
        switch self {
        case .invalidTargetURL:
            ["FileError": "Invalid target URL — could not resolve destination directory"]
        case .removeFailed(let error):
            ["FileError": "Failed to remove existing file: \(error.localizedDescription)"]
        case .copyFailed(let error):
            ["FileError": "Failed to copy file: \(error.localizedDescription)"]
        }
    }
}

//
//  FileError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

public enum FileError: Error, LoggableError {
    case invalidTargetURL
    case removeFailed(Error)
    case copyFailed(Error)

    var logDescription: String {
        switch self {
        case .invalidTargetURL:
            "Invalid target URL — could not resolve destination directory"
        case .removeFailed(let error):
            "Failed to remove existing file: \(error.localizedDescription)"
        case .copyFailed(let error):
            "Failed to copy file: \(error.localizedDescription)"
        }
    }
}

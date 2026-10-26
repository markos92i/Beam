//
//  FileError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

/// Failures of a file operation. Their ``APIError/kind`` is `.storage` in whichever layer they surface.
public enum FileError: Error, LoggableError {
    case copyFailed(CocoaError)
    /// A finished download couldn't be moved out of its temporary location.
    case moveFailed(CocoaError)
    /// A file to upload is missing or unreadable.
    case readFailed(CocoaError)
    /// A background upload's body or a stored download's folder couldn't be written.
    case writeFailed(CocoaError)

    var logDescription: String {
        switch self {
        case .copyFailed(let error):
            "Failed to copy file: \(error.fileDescription)"
        case .moveFailed(let error):
            "Failed to move downloaded file: \(error.fileDescription)"
        case .readFailed(let error):
            "Failed to read file: \(error.fileDescription)"
        case .writeFailed(let error):
            "Failed to write file: \(error.fileDescription)"
        }
    }
}

// MARK: - Bridging

extension CocoaError {
    /// Foundation file APIs are untyped but document `CocoaError`; anything else becomes the underlying error.
    init(bridging error: any Error, fallback: CocoaError.Code) {
        self = error as? CocoaError ?? CocoaError(fallback, userInfo: [NSUnderlyingErrorKey: error])
    }

    fileprivate var fileDescription: String {
        guard let path = filePath ?? url?.path(percentEncoded: false) else { return localizedDescription }
        let home = NSHomeDirectory()
        let shown = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        return "\(localizedDescription) [\(shown)]"
    }
}

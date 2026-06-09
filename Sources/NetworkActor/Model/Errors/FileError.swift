//
//  FileError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

public enum FileError: Error {
    case invalidTargetURL
    case removeFailed(Error)
    case copyFailed(Error)
}

extension FileError: CustomNSError {
    public static var errorDomain: String { "network.FileError" }
        
    public var errorUserInfo: [String: Any] {
        [
            NSLocalizedDescriptionKey: "FileError: \(self)", // Main Message
        ]
    }
}

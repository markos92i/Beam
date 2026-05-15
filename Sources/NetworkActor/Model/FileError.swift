//
//  FileError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation
import UniformTypeIdentifiers

public enum FileError: Error {
    case invalidTargetURL
    case removeFailed(Error)
    case copyFailed(Error)
}

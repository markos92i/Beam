//
//  LoggableError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 12/06/2026.
//

import Foundation

/// Errors that provide a human-readable description for structured logging.
///
/// The logger renders `logDescription` as-is — multiline strings are supported
/// and will be printed preserving line breaks.
protocol LoggableError: Error {
    var logDescription: String { get }
}

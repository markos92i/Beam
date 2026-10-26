//
//  LoggableError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 12/06/2026.
//

import Foundation

/// The logger prints `logDescription` as-is, line breaks included.
protocol LoggableError: Error {
    var logDescription: String { get }
}

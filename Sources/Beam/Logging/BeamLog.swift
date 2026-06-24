//
//  BeamLog.swift
//  Beam
//
//  Public logging configuration.
//

import Foundation

/// Global logging configuration for Beam.
public enum BeamLog {
    /// Enables/disables all Beam logging.
    public static var enabled: Bool {
        get { BeamLogger.enabled }
        set { BeamLogger.enabled = newValue }
    }

    /// Global minimum log level.
    public static var level: LogLevel {
        get { BeamLogger.level }
        set { BeamLogger.level = newValue }
    }

    /// Prints full request and response bodies to console.
    public static var verbose: Bool {
        get { BeamLogger.verbose }
        set { BeamLogger.verbose = newValue }
    }
}

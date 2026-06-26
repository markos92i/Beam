//
//  BeamLogger.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 12/06/2026.
//

import Foundation
import os

// MARK: - LogLevel

/// Log severity level.
public enum LogLevel: Int, Sendable, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case off = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Maps the semantic level to the corresponding `OSLogType`.
    var osLogType: OSLogType {
        switch self {
        case .debug:   .debug
        case .info:    .info
        case .warning: .error
        case .error:   .fault
        case .off:     .info
        }
    }
}

// MARK: - BeamLogger

/// Centralized logger with categories, signposts, and privacy.
public struct BeamLogger: Sendable {

    // MARK: - Global Configuration

    /// Enables/disables all Beam logs globally.
    public nonisolated(unsafe) static var enabled = true

    /// Global minimum level. Used as fallback when no instance level is set.
    public nonisolated(unsafe) static var level: LogLevel = .debug

    /// When true, prints full request and response bodies to console.
    public nonisolated(unsafe) static var verbose = false

    // MARK: - Instance Configuration

    /// Instance-level minimum. Falls back to `BeamLogger.level` when nil.
    private let instanceLevel: LogLevel?

    /// Effective level: instance if set, global otherwise.
    private var effectiveLevel: LogLevel { instanceLevel ?? Self.level }

    init(level: LogLevel? = nil) {
        self.instanceLevel = level
    }

    // MARK: - Subsystem

    private static let subsystem = "com.beam"

    // MARK: - Categorized Loggers

    private func logger(for category: LogEvent.LogCategory) -> os.Logger {
        switch category {
        case .http:      os.Logger(subsystem: Self.subsystem, category: "http")
        case .websocket: os.Logger(subsystem: Self.subsystem, category: "websocket")
        case .auth:      os.Logger(subsystem: Self.subsystem, category: "auth")
        case .error:     os.Logger(subsystem: Self.subsystem, category: "error")
        }
    }

    // MARK: - Signposts

    private let signposter = OSSignposter(subsystem: BeamLogger.subsystem, category: "http")

    // MARK: - Constants

    private let maxBodySize = 300

    // MARK: - Unified Log Entry Point

    /// Logs a structured event. Guard, format, and emit happen in one place.
    func log(_ event: LogEvent) {
        guard Self.enabled, effectiveLevel <= event.meta.level else { return }

        let config = RenderConfig(verbose: Self.verbose, maxBodySize: maxBodySize)
        let output = event.rendered(in: config)
        emit(output, to: logger(for: event.meta.category), level: event.meta.level.osLogType)
    }

    // MARK: - Signpost API

    /// Begins a signpost interval for an HTTP request.
    func beginRequest(id: String, method: String, path: String) -> OSSignpostIntervalState {
        signposter.beginInterval("request", id: .exclusive, "\(method, privacy: .public) \(path, privacy: .public) [\(id, privacy: .public)]")
    }

    /// Ends the signpost interval for an HTTP request.
    func endRequest(_ state: OSSignpostIntervalState, status: Int) {
        signposter.endInterval("request", state, "\(status, privacy: .public)")
    }

    // MARK: - Emit

    /// Sends the rendered output to the os.Logger at the given level.
    private func emit(_ output: String, to logger: os.Logger, level: OSLogType = .info) {
        switch level {
        case .debug: logger.debug("\(output, privacy: .public)")
        case .info: logger.info("\(output, privacy: .public)")
        case .error: logger.warning("\(output, privacy: .public)")
        case .fault: logger.fault("\(output, privacy: .public)")
        default: logger.info("\(output, privacy: .public)")
        }
    }
}

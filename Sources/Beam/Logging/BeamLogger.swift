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
}

// MARK: - BeamLogger

/// Centralized logger with categories, signposts, and privacy.
struct BeamLogger: Sendable {

    // MARK: - Global Configuration

    /// Enables/disables all Beam logs globally.
    nonisolated(unsafe) static var enabled = true

    /// Global minimum level. Used as fallback when no instance level is set.
    nonisolated(unsafe) static var level: LogLevel = .debug

    /// When true, prints full request and response bodies to console.
    nonisolated(unsafe) static var verbose = false

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

    private let loggers: [LogEvent.LogCategory: os.Logger] = [
        .http: os.Logger(subsystem: BeamLogger.subsystem, category: "http"),
        .websocket: os.Logger(subsystem: BeamLogger.subsystem, category: "websocket"),
        .auth: os.Logger(subsystem: BeamLogger.subsystem, category: "auth"),
        .error: os.Logger(subsystem: BeamLogger.subsystem, category: "error")
    ]

    // MARK: - Signposts

    private let signposter = OSSignposter(subsystem: BeamLogger.subsystem, category: "http")

    // MARK: - Constants

    private let maxBodySize = 300

    // MARK: - Unified Log Entry Point

    /// Logs a structured event. Guard, format, and emit happen in one place.
    func log(_ event: LogEvent) {
        guard Self.enabled, effectiveLevel <= event.level else { return }

        let lines = event.lines(verbose: Self.verbose, maxBodySize: maxBodySize)
        let block = LogBlock(lines, style: event.style)
        let logger = loggers[event.category]!
        emit(block, to: logger, level: event.osLevel)
    }

    // MARK: - Signpost API

    /// Begins a signpost interval for an HTTP request.
    func beginRequest(rid: String, method: String, path: String) -> OSSignpostIntervalState {
        signposter.beginInterval("request", id: .exclusive, "\(method, privacy: .public) \(path, privacy: .public) [\(rid, privacy: .public)]")
    }

    /// Ends the signpost interval for an HTTP request.
    func endRequest(_ state: OSSignpostIntervalState, status: Int) {
        signposter.endInterval("request", state, "\(status, privacy: .public)")
    }

    // MARK: - Emit

    /// Renders the block and sends it to the os.Logger at the given level.
    private func emit(_ block: LogBlock, to logger: os.Logger, level: OSLogType = .info) {
        let output = block.rendered()
        switch level {
        case .debug: logger.debug("\(output, privacy: .public)")
        case .info: logger.info("\(output, privacy: .public)")
        case .error: logger.warning("\(output, privacy: .public)")
        case .fault: logger.fault("\(output, privacy: .public)")
        default: logger.info("\(output, privacy: .public)")
        }
    }
}

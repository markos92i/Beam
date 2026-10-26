//
//  BeamLogger.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 12/06/2026.
//

import Foundation
import os
import Synchronization

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

    /// Same mapping as `os.Logger`: `.fault` is for process bugs, not failed calls.
    var osLogType: OSLogType {
        switch self {
        case .debug:   .debug
        case .info:    .info
        case .warning: .error
        case .error:   .error
        case .off:     .info
        }
    }
}

// MARK: - BeamLogger

/// Centralized logger with categories, signposts, and privacy.
public struct BeamLogger: Sendable {

    // MARK: - Global Configuration

    #if DEBUG
    private static let defaultLevel = LogLevel.debug
    #else
    private static let defaultLevel = LogLevel.warning
    #endif

    // Atomic: read from any thread on every log call, writable at runtime.
    private static let _level = Atomic<Int>(defaultLevel.rawValue)

    /// Global minimum level for APIs without `@API(logLevel:)`; `.off` silences all of Beam.
    public static var level: LogLevel {
        get { LogLevel(rawValue: _level.load(ordering: .relaxed)) ?? defaultLevel }
        set { _level.store(newValue.rawValue, ordering: .relaxed) }
    }

    // MARK: - Instance Configuration

    private let instanceLevel: LogLevel?

    var effectiveLevel: LogLevel { instanceLevel ?? Self.level }

    func logs(_ level: LogLevel, global: LogLevel = BeamLogger.level) -> Bool {
        global != .off && (instanceLevel ?? global) <= level
    }

    init(level: LogLevel? = nil) {
        self.instanceLevel = level
    }

    // MARK: - Subsystem

    private static let subsystem = "com.beam"

    // MARK: - Categorized Loggers

    private static let httpLogger = os.Logger(subsystem: subsystem, category: "http")
    private static let websocketLogger = os.Logger(subsystem: subsystem, category: "websocket")
    private static let authLogger = os.Logger(subsystem: subsystem, category: "auth")
    private static let errorLogger = os.Logger(subsystem: subsystem, category: "error")

    private func logger(for category: LogEvent.LogCategory) -> os.Logger {
        switch category {
        case .http:      Self.httpLogger
        case .websocket: Self.websocketLogger
        case .auth:      Self.authLogger
        case .error:     Self.errorLogger
        }
    }

    // MARK: - Signposts

    private static let signposter = OSSignposter(subsystem: subsystem, category: "http")

    // MARK: - Unified Log Entry Point

    func log(_ event: LogEvent) {
        guard logs(event.meta.level) else { return }

        // Bodies are debug detail; error responses always show theirs.
        let output = event.rendered(bodies: logs(.debug))
        emit(output, to: logger(for: event.meta.category), level: event.meta.level.osLogType)
    }

    // MARK: - Signpost API

    /// Own signpost ID per interval: concurrent requests can't share `.exclusive`.
    func beginRequest(id: String, method: String, path: String) -> OSSignpostIntervalState {
        let signpostID = Self.signposter.makeSignpostID()
        // The path may carry identifiers: private outside Debug.
        #if DEBUG
        return Self.signposter.beginInterval("request", id: signpostID, "\(method, privacy: .public) \(path, privacy: .public) [\(id, privacy: .public)]")
        #else
        return Self.signposter.beginInterval("request", id: signpostID, "\(method, privacy: .public) \(path, privacy: .private) [\(id, privacy: .public)]")
        #endif
    }

    func endRequest(_ state: OSSignpostIntervalState, status: Int) {
        Self.signposter.endInterval("request", state, "\(status, privacy: .public)")
    }

    // MARK: - Emit

    /// Output may hold personal data: public only in Debug. `privacy:` must be a literal.
    private func emit(_ output: String, to logger: os.Logger, level: OSLogType) {
        #if DEBUG
        logger.log(level: level, "\(output, privacy: .public)")
        #else
        logger.log(level: level, "\(output, privacy: .private)")
        #endif
    }
}

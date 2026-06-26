//
//  RenderContext.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 25/06/2026.
//

import Foundation

// MARK: - RenderContext

/// Encapsulates all rendering configuration for log events.
///
/// Extend this struct to add new rendering options without changing
/// the `lines(in:)` signature or any call site.
struct RenderConfig: Sendable {
    /// When true, full request/response bodies are included in output.
    let verbose: Bool

    /// Maximum body size (in characters) when verbose mode is active.
    let maxBodySize: Int

    /// Default config built from current global logger settings.
    static var current: RenderConfig {
        RenderConfig(verbose: BeamLogger.verbose, maxBodySize: 300)
    }
}

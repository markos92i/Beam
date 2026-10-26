//
//  RenderConfig.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 25/06/2026.
//

import Foundation

// MARK: - RenderConfig

struct RenderConfig: Sendable {
    let verbose: Bool

    let maxBodySize: Int

    static var current: RenderConfig {
        RenderConfig(verbose: BeamLogger.verbose, maxBodySize: BeamLogger.maxBodySize)
    }
}

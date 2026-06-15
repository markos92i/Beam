//
//  ProgressHandler.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

/// Closure type for receiving progress updates during network operations.
/// Dispatched on MainActor for safe UI updates.
public typealias ProgressHandler = @MainActor @Sendable (Progress) -> Void

//
//  DownloadTask.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

// MARK: - ProgressHandler

/// Closure type for receiving progress updates during network operations.
/// Dispatched on MainActor for safe UI updates.
public typealias ProgressHandler = @MainActor @Sendable (Progress) -> Void

// MARK: - DownloadTask

/// A typed handle for download operations using background-compatible tasks.
/// Provides progress tracking via Foundation `Progress`, cancellation with resume data, and typed throws.
public struct DownloadTask<Failure: Sendable>: Sendable, Identifiable {
    public let id: String
    public let progress: Progress
    private let endpoint: Endpoint<URL, Failure>

    public init(endpoint: Endpoint<URL, Failure>) {
        self.endpoint = endpoint
        self.id = endpoint.id
        self.progress = endpoint.progress
    }

    /// Starts the download and returns the file URL on success.
    public func start() async throws(APIError<Failure>) -> URL {
        try await endpoint.downloadTask()
    }

    /// Resumes a previously interrupted download using stored resume data.
    public func start(resumeFrom data: Data) async throws(APIError<Failure>) -> URL {
        try await endpoint.downloadTask(resumeFrom: data)
    }

    /// Cancels the download and returns resume data if available.
    @discardableResult
    public func cancel() async -> Data? {
        await endpoint.cancel()
    }
}

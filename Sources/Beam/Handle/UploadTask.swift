//
//  UploadTask.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

// MARK: - UploadTask

/// A typed handle for upload operations using background-compatible tasks.
/// Provides progress tracking via Foundation `Progress`, cancellation with resume data, and typed throws.
public struct UploadTask<Success: Sendable, Failure: Sendable>: Sendable, Identifiable {
    public let id: String
    public let progress: Progress
    private let endpoint: Endpoint<Success, Failure>

    public init(endpoint: Endpoint<Success, Failure>) {
        self.endpoint = endpoint
        self.id = endpoint.id
        self.progress = endpoint.progress
    }

    /// Starts the upload using the body configured in the endpoint.
    @discardableResult
    public func start() async throws(APIError<Failure>) -> Success {
        try await endpoint.uploadTask()
    }

    /// Starts the upload with explicit data.
    @discardableResult
    public func start(data: Data) async throws(APIError<Failure>) -> Success {
        try await endpoint.uploadTask(data: data)
    }

    /// Starts the upload from a file URL.
    @discardableResult
    public func start(url: URL) async throws(APIError<Failure>) -> Success {
        try await endpoint.uploadTask(url: url)
    }

    /// Resumes a previously interrupted upload using stored resume data.
    @discardableResult
    public func start(resumeFrom data: Data) async throws(APIError<Failure>) -> Success {
        try await endpoint.upload(resumeFrom: data)
    }

    /// Cancels the upload and returns resume data if available.
    @discardableResult
    public func cancel() async -> Data? {
        await endpoint.cancel()
    }
}

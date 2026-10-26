//
//  TransferTask.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

// MARK: - TransferTask

/// An upload or download driven by the session delegate; `id` and `progress` exist before it starts.
public struct TransferTask<Success: Sendable, Failure: Sendable>: Sendable, Identifiable {
    /// The call's id, as in the logs.
    public var id: String { call.id }
    /// Read `fractionCompleted`: units are a fixed scale, not bytes; it restarts on every attempt.
    public var progress: Progress { call.client.progress }
    let call: Call<Success, Failure>
    let transfer: @Sendable (Call<Success, Failure>, _ resume: Data?) async throws(APIError<Failure>) -> Success

    /// Starts the transfer, or resumes one; if resuming fails, later attempts start over.
    @discardableResult
    public func start(resumeFrom data: Data? = nil) async throws(APIError<Failure>) -> Success {
        try await call.client.run { [call, transfer] () throws(APIError<Failure>) in try await transfer(call, data) }
    }

    /// Cancels the transfer and returns resume data if available, also after a failed start.
    @discardableResult
    public func cancel() async -> Data? {
        await call.client.cancel()
    }
}

/// The handle of an upload.
public typealias UploadTask<Success: Sendable, Failure: Sendable> = TransferTask<Success, Failure>

/// The handle of a download, which returns the downloaded file.
public typealias DownloadTask<Failure: Sendable> = TransferTask<URL, Failure>

// MARK: - BackgroundTransferTask

/// A transfer on a background session, which goes on while the app is suspended or terminated.
public struct BackgroundTransferTask<Success: Sendable, Failure: Sendable>: Sendable, Identifiable {
    /// The call's id, as in the logs; the transfer's id is the one given to `start(id:)`.
    public var id: String { call.id }
    /// See ``TransferTask/progress``.
    public var progress: Progress { call.client.progress }
    let call: Call<Success, Failure>
    let transfer: @Sendable (Call<Success, Failure>, _ id: String, _ resume: Data?) async throws(APIError<Failure>) -> Success

    /// Starts the transfer, or attaches to the one in flight with the same `id` on this route.
    @discardableResult
    public func start(id: String) async throws(APIError<Failure>) -> Success {
        try await start(id: id, resume: nil)
    }

    /// See ``TransferTask/cancel()``.
    @discardableResult
    public func cancel() async -> Data? {
        await call.client.cancel()
    }

    func start(id: String, resume: Data?) async throws(APIError<Failure>) -> Success {
        try await call.client.run { [call, transfer] () throws(APIError<Failure>) in try await transfer(call, id, resume) }
    }
}

extension BackgroundTransferTask where Success == URL {
    /// Like ``start(id:)``, resuming an interrupted download from `data`.
    @discardableResult
    public func start(id: String, resumeFrom data: Data?) async throws(APIError<Failure>) -> URL {
        try await start(id: id, resume: data)
    }
}

/// The handle of an upload on a background session.
public typealias BackgroundUploadTask<Success: Sendable, Failure: Sendable> = BackgroundTransferTask<Success, Failure>

/// The handle of a download on a background session.
public typealias BackgroundDownloadTask<Failure: Sendable> = BackgroundTransferTask<URL, Failure>

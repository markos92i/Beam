//
//  Session.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 3/7/26.
//

import Foundation

/// Beam-managed URLSession wrapper that owns the session and its delegate.
///
/// Use `Session` when you need Beam to control the session lifecycle — required
/// for background transfers and SSL pinning. For simple foreground requests or
/// testing, you can still pass a raw `URLSession` via `SessionProtocol`.
///
/// ```swift
/// // Background session with SSL pinning
/// let session = Session(
///     configuration: .background(withIdentifier: "com.myapp.transfers"),
///     trustPolicy: MyTrustPolicy()
/// )
///
/// // Default foreground session
/// let session = Session()
/// ```
public final class Session: SessionProtocol, @unchecked Sendable {
    private let urlSession: URLSession
    private let sessionDelegate: SessionDelegate

    /// The session identifier, if using a background configuration.
    public var identifier: String? { urlSession.configuration.identifier }

    /// Whether this session uses a background configuration.
    public var isBackground: Bool { identifier != nil }

    public init(
        configuration: URLSessionConfiguration = .default,
        trustPolicy: (any TransportTrustPolicy)? = nil
    ) {
        self.sessionDelegate = SessionDelegate(trustPolicy: trustPolicy)
        self.urlSession = URLSession(
            configuration: configuration,
            delegate: sessionDelegate,
            delegateQueue: nil
        )
    }

    /// Convenience initializer for background sessions.
    public convenience init(
        identifier: String,
        trustPolicy: (any TransportTrustPolicy)? = nil,
        isDiscretionary: Bool = false,
        sessionSendsLaunchEvents: Bool = true
    ) {
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = isDiscretionary
        config.sessionSendsLaunchEvents = sessionSendsLaunchEvents
        self.init(configuration: config, trustPolicy: trustPolicy)
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

    // MARK: - SessionProtocol (async convenience)

    public func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await urlSession.bytes(for: request, delegate: delegate)
    }

    public func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        try await urlSession.data(for: request, delegate: delegate)
    }

    public func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (URL, URLResponse) {
        try await urlSession.download(for: request, delegate: delegate)
    }

    public func download(resumeFrom data: Data, delegate: URLSessionTaskDelegate?) async throws -> (URL, URLResponse) {
        try await urlSession.download(resumeFrom: data, delegate: delegate)
    }

    public func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        try await urlSession.upload(for: request, from: data, delegate: delegate)
    }

    public func upload(for request: URLRequest, fromFile url: URL, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        try await urlSession.upload(for: request, fromFile: url, delegate: delegate)
    }

    public func upload(resumeFrom data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        try await urlSession.upload(resumeFrom: data, delegate: delegate)
    }

    // MARK: - SessionProtocol (task-based, background-compatible)

    public func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
        urlSession.downloadTask(with: request)
    }

    public func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask {
        urlSession.downloadTask(withResumeData: data)
    }

    public func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask {
        urlSession.uploadTask(with: request, from: data)
    }

    public func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask {
        urlSession.uploadTask(with: request, fromFile: url)
    }

    public func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask {
        urlSession.webSocketTask(with: request)
    }

    // MARK: - Task Management

    /// All tasks currently running on this session.
    public var allTasks: [URLSessionTask] {
        get async { await urlSession.allTasks }
    }

    /// Cancels all in-flight tasks on this session.
    public func cancelAllTasks() async {
        for task in await allTasks { task.cancel() }
    }

    // MARK: - Background Transfer Results

    /// Results from background transfers completed while the app was suspended or terminated.
    ///
    /// Consumes all accumulated results — subsequent calls return an empty array
    /// until new background events arrive.
    public var pendingResults: [BackgroundTransferResult] {
        sessionDelegate.consumePendingResults()
    }

    /// An async stream of background transfer results, yielding each result as it arrives.
    ///
    /// Useful inside `.backgroundTask(.urlSession("..."))` to process results one by one.
    /// The stream finishes when all pending events have been delivered.
    public var resultStream: AsyncStream<BackgroundTransferResult> {
        AsyncStream { continuation in
            // Yield any already-accumulated results
            for result in sessionDelegate.consumePendingResults() {
                continuation.yield(result)
            }
            // Stream future results as they arrive
            sessionDelegate.setResultsContinuation(continuation)
        }
    }
}

//
//  Session.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 3/7/26.
//

import Foundation

// MARK: - Kinds

/// A foreground session: every kind of call, while the app runs.
public enum Foreground {}

/// A background session: uploads and downloads that go on while the app is suspended or terminated.
public enum Background {}

// MARK: - Mode

/// How a ``Session`` is created; the mode decides whether it is foreground or background.
public struct SessionMode<Kind>: Sendable {
    let makeConfiguration: @Sendable () -> URLSessionConfiguration
}

extension SessionMode where Kind == Foreground {
    /// `URLSessionConfiguration.default`: persistent cache, cookies and credentials.
    public static var `default`: SessionMode { SessionMode { .default } }

    /// `URLSessionConfiguration.ephemeral`: nothing is persisted to disk.
    public static var ephemeral: SessionMode { SessionMode { .ephemeral } }
}

extension SessionMode where Kind == Background {
    /// `URLSessionConfiguration.background(withIdentifier:)`. Use the same identifier
    /// on every launch, to reconnect with the transfers of the previous one.
    public static func background(_ identifier: String) -> SessionMode {
        SessionMode { .background(withIdentifier: identifier) }
    }
}

// MARK: - Session

/// Beam's URLSession: Beam owns its delegate (trust, delegate-driven transfers, background events).
/// A background session must be one per identifier, alive for the whole process.
public final class Session<Kind>: Sendable {
    let urlSession: URLSession
    public let sessionDelegate: SessionDelegate
    let registry: BackgroundTaskRegistry

    /// `trustPolicy` evaluates server trust (SSL pinning) for every task.
    public init(
        _ mode: SessionMode<Kind> = .default,
        trustPolicy: (any TransportTrustPolicy)? = nil,
        configure: (URLSessionConfiguration) -> Void = { _ in }
    ) {
        let configuration = mode.makeConfiguration()
        configure(configuration)
        // Only a background session keeps unawaited transfers: they can finish while the app isn't running.
        self.sessionDelegate = SessionDelegate(
            trustPolicy: trustPolicy,
            store: configuration.identifier.map(TransferStore.init(sessionIdentifier:))
        )
        self.urlSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
        self.registry = BackgroundTaskRegistry(session: urlSession)
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

    // MARK: - Task Management

    /// All tasks in the session, including those reconnected after a relaunch.
    public var allTasks: [URLSessionTask] {
        get async { await urlSession.allTasks }
    }

    /// Cancels every task of the session.
    public func cancelAllTasks() async {
        for task in await allTasks { task.cancel() }
    }
}

// MARK: - Foreground

extension Session: SessionProtocol where Kind == Foreground {
    // URLSession's async methods are untyped: this is the single bridge to `URLError`.

    public func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URLSession.AsyncBytes, URLResponse) {
        do { return try await urlSession.bytes(for: request, delegate: delegate) } catch { throw URLError(bridging: error) }
    }

    public func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        do { return try await urlSession.data(for: request, delegate: delegate) } catch { throw URLError(bridging: error) }
    }

    public func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) {
        do { return try await urlSession.download(for: request, delegate: delegate) } catch { throw URLError(bridging: error) }
    }

    public func download(resumeFrom data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) {
        do { return try await urlSession.download(resumeFrom: data, delegate: delegate) } catch { throw URLError(bridging: error) }
    }

    public func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        do { return try await urlSession.upload(for: request, from: data, delegate: delegate) } catch { throw URLError(bridging: error) }
    }

    public func upload(for request: URLRequest, fromFile url: URL, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        do { return try await urlSession.upload(for: request, fromFile: url, delegate: delegate) } catch { throw URLError(bridging: error) }
    }

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

    public func uploadTask(withResumeData data: Data) -> URLSessionUploadTask {
        urlSession.uploadTask(withResumeData: data)
    }

    public func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask {
        urlSession.webSocketTask(with: request)
    }
}

//
//  SessionDelegate.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 3/7/26.
//

import Foundation

/// Internal session-level delegate that owns the URLSession lifecycle.
///
/// Handles:
/// - Server trust evaluation (SSL pinning) via an injected ``TransportTrustPolicy``.
/// - Background session event completion signaling.
/// - Per-task delegate forwarding for foreground task-based operations.
/// - Awaitable task completion for background sessions via stored continuations.
/// - Accumulating results when no continuation or delegate exists (app relaunch scenario).
public final class SessionDelegate: NSObject, @unchecked Sendable {
    private let trustPolicy: (any TransportTrustPolicy)?

    /// Accumulated results from background transfers completed without a waiter.
    private(set) var pendingResults: [BackgroundTransferResult] = []

    /// Accumulated response data for upload tasks (keyed by task identifier).
    private var uploadDataBuffers: [Int: Data] = [:]

    /// Continuation for streaming pending results to consumers.
    private var resultsContinuation: AsyncStream<BackgroundTransferResult>.Continuation?

    /// Continuations waiting for download task completion (keyed by task identifier).
    private var downloadContinuations: [Int: CheckedContinuation<(URL, URLResponse), Error>] = [:]

    /// Continuations waiting for upload task completion (keyed by task identifier).
    private var uploadContinuations: [Int: CheckedContinuation<(Data, URLResponse), Error>] = [:]

    init(trustPolicy: (any TransportTrustPolicy)? = nil) {
        self.trustPolicy = trustPolicy
    }

    // MARK: - Awaitable Task Completion

    /// Awaits completion of a download task. Stores a continuation that the
    /// delegate callbacks will resume when the transfer finishes.
    /// The task is resumed internally — do not call `task.resume()` beforehand.
    public func awaitDownload(for task: URLSessionDownloadTask) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            downloadContinuations[task.taskIdentifier] = continuation
            task.resume()
        }
    }

    /// Awaits completion of an upload task. Stores a continuation that the
    /// delegate callbacks will resume when the transfer finishes.
    /// The task is resumed internally — do not call `task.resume()` beforehand.
    public func awaitUpload(for task: URLSessionTask) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            uploadContinuations[task.taskIdentifier] = continuation
            task.resume()
        }
    }

    // MARK: - Pending Results

    /// Removes and returns all accumulated pending results.
    func consumePendingResults() -> [BackgroundTransferResult] {
        let results = pendingResults
        pendingResults = []
        return results
    }

    /// Sets a continuation for streaming results as they arrive.
    func setResultsContinuation(_ continuation: AsyncStream<BackgroundTransferResult>.Continuation?) {
        resultsContinuation = continuation
    }

    private func addResult(_ result: BackgroundTransferResult) {
        pendingResults.append(result)
        resultsContinuation?.yield(result)
    }
}

// MARK: - URLSessionDelegate

extension SessionDelegate: URLSessionDelegate {
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let trustPolicy {
            return trustPolicy.evaluate(challenge: challenge)
        }
        return (.performDefaultHandling, nil)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        resultsContinuation?.finish()
        resultsContinuation = nil
    }
}

// MARK: - URLSessionTaskDelegate

extension SessionDelegate: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // 1. Upload continuation waiting — resume it.
        if let continuation = uploadContinuations.removeValue(forKey: task.taskIdentifier) {
            if let error {
                continuation.resume(throwing: error)
            } else {
                let data = uploadDataBuffers.removeValue(forKey: task.taskIdentifier) ?? Data()
                continuation.resume(returning: (data, task.response!))
            }
            return
        }

        // 2. Download continuation that wasn't resolved by didFinishDownloadingTo (error case).
        if let continuation = downloadContinuations.removeValue(forKey: task.taskIdentifier) {
            continuation.resume(throwing: error ?? URLError(.cannotParseResponse))
            return
        }

        // 3. Foreground path — forward to per-task delegate.
        if task.delegate != nil {
            task.delegate?.urlSession?(session, task: task, didCompleteWithError: error)
            return
        }

        // 4. No waiter (app relaunched) — accumulate the result.
        let originalURL = task.originalRequest?.url
        let taskDescription = task.taskDescription
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode

        if let error {
            let transportError: TransportError = switch error {
            case let urlError as URLError: .url(urlError)
            case let transport as TransportError: transport
            default: .unknown(error)
            }
            addResult(BackgroundTransferResult(
                originalURL: originalURL,
                taskDescription: taskDescription,
                statusCode: statusCode,
                outcome: .failed(transportError)
            ))
        } else if task is URLSessionUploadTask {
            let data = uploadDataBuffers.removeValue(forKey: task.taskIdentifier) ?? Data()
            addResult(BackgroundTransferResult(
                originalURL: originalURL,
                taskDescription: taskDescription,
                statusCode: statusCode,
                outcome: .uploaded(data)
            ))
        }
        // Downloads are handled in didFinishDownloadingTo
    }
}

// MARK: - URLSessionDownloadDelegate

extension SessionDelegate: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 1. Download continuation waiting — resume it.
        if let continuation = downloadContinuations.removeValue(forKey: downloadTask.taskIdentifier) {
            let safeCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.copyItem(at: location, to: safeCopy)
                continuation.resume(returning: (safeCopy, downloadTask.response!))
            } catch {
                continuation.resume(throwing: error)
            }
            return
        }

        // 2. Foreground path — forward to per-task delegate.
        if let taskDelegate = downloadTask.delegate as? URLSessionDownloadDelegate {
            taskDelegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
            return
        }

        // 3. No waiter — copy file and accumulate result.
        let safeCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent("beam_bg_\(UUID().uuidString)")
            .appendingPathExtension(location.pathExtension)

        let originalURL = downloadTask.originalRequest?.url
        let taskDescription = downloadTask.taskDescription
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode

        do {
            try FileManager.default.copyItem(at: location, to: safeCopy)
            addResult(BackgroundTransferResult(
                originalURL: originalURL,
                taskDescription: taskDescription,
                statusCode: statusCode,
                outcome: .downloaded(safeCopy)
            ))
        } catch {
            addResult(BackgroundTransferResult(
                originalURL: originalURL,
                taskDescription: taskDescription,
                statusCode: statusCode,
                outcome: .failed(.unknown(error))
            ))
        }
    }
}

// MARK: - URLSessionDataDelegate

extension SessionDelegate: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // 1. Upload continuation waiting — buffer data for it.
        if uploadContinuations[dataTask.taskIdentifier] != nil {
            uploadDataBuffers[dataTask.taskIdentifier, default: Data()].append(data)
            return
        }

        // 2. Foreground path — forward to per-task delegate.
        if let taskDelegate = dataTask.delegate as? URLSessionDataDelegate {
            taskDelegate.urlSession?(session, dataTask: dataTask, didReceive: data)
            return
        }

        // 3. No waiter — buffer data for the upload result.
        uploadDataBuffers[dataTask.taskIdentifier, default: Data()].append(data)
    }
}

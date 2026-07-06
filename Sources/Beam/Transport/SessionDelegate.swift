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
/// - Per-task delegate forwarding for task-based operations.
/// - Accumulating results when no per-task delegate exists (app relaunch scenario).
final class SessionDelegate: NSObject, @unchecked Sendable {
    private let trustPolicy: (any TransportTrustPolicy)?

    /// Accumulated results from background transfers completed without a per-task delegate.
    private(set) var pendingResults: [BackgroundTransferResult] = []

    /// Accumulated response data for upload tasks (keyed by task identifier).
    private var uploadDataBuffers: [Int: Data] = [:]

    /// Continuation for streaming pending results to consumers.
    private var resultsContinuation: AsyncStream<BackgroundTransferResult>.Continuation?

    init(trustPolicy: (any TransportTrustPolicy)? = nil) {
        self.trustPolicy = trustPolicy
    }

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
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let trustPolicy {
            return trustPolicy.evaluate(challenge: challenge)
        }
        return (.performDefaultHandling, nil)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        resultsContinuation?.finish()
        resultsContinuation = nil
    }
}

// MARK: - URLSessionTaskDelegate

extension SessionDelegate: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // If a per-task delegate exists, forward and let it handle everything.
        if task.delegate != nil {
            task.delegate?.urlSession?(session, task: task, didCompleteWithError: error)
            return
        }

        // No per-task delegate (app was relaunched) — accumulate the result.
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
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // If a per-task delegate exists, forward to it.
        if let taskDelegate = downloadTask.delegate as? URLSessionDownloadDelegate {
            taskDelegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
            return
        }

        // No per-task delegate — copy file to a stable location and accumulate result.
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
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // If a per-task delegate exists, forward to it.
        if let taskDelegate = dataTask.delegate as? URLSessionDataDelegate {
            taskDelegate.urlSession?(session, dataTask: dataTask, didReceive: data)
            return
        }

        // No per-task delegate — buffer data for the upload result.
        uploadDataBuffers[dataTask.taskIdentifier, default: Data()].append(data)
    }
}

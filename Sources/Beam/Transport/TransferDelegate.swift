//
//  TransferDelegate.swift
//  Beam
//
//  Minimal per-task delegate that bridges URLSession delegate callbacks
//  to async/await via CheckedContinuation. Used by the task-based path
//  (downloadTask/uploadTask) for background-compatible transfers.
//

import Foundation

// MARK: - DownloadTransferDelegate

/// Bridges `URLSessionDownloadDelegate` completion to a `CheckedContinuation`.
/// Only handles the result delivery — progress comes from `task.progress`.
///
/// Guards against permanent hangs: if `didCompleteWithError` arrives with nil
/// but `didFinishDownloadingTo` was never called, the continuation is resumed
/// with an error instead of hanging indefinitely.
final class DownloadTransferDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let continuation: CheckedContinuation<(URL, URLResponse), Error>
    private var didResume = false

    init(continuation: CheckedContinuation<(URL, URLResponse), Error>) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !didResume else { return }
        // URLSession deletes the file after this method returns — copy to a safe location
        let safeCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: safeCopy)
            guard let response = downloadTask.response else {
                didResume = true
                continuation.resume(throwing: URLError(.badServerResponse))
                return
            }
            didResume = true
            continuation.resume(returning: (safeCopy, response))
        } catch {
            didResume = true
            continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard !didResume else { return }
        didResume = true

        if let error {
            continuation.resume(throwing: error)
        } else {
            // didFinishDownloadingTo was never called — treat as failed transfer
            continuation.resume(throwing: URLError(.cannotParseResponse))
        }
    }
}

// MARK: - UploadTransferDelegate

/// Bridges `URLSessionDataDelegate` completion to a `CheckedContinuation`.
/// Accumulates response data chunks and delivers the final result.
///
/// Includes a `didResume` guard to prevent double-resume in edge cases
/// where delegate callbacks fire unexpectedly after completion.
final class UploadTransferDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: CheckedContinuation<(Data, URLResponse), Error>
    private var responseData = Data()
    private var didResume = false

    init(continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard !didResume else { return }
        didResume = true

        if let error {
            continuation.resume(throwing: error)
        } else {
            guard let response = task.response else {
                continuation.resume(throwing: URLError(.badServerResponse))
                return
            }
            continuation.resume(returning: (responseData, response))
        }
    }
}


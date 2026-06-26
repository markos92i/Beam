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
final class DownloadTransferDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let continuation: CheckedContinuation<(URL, URLResponse), Error>

    init(continuation: CheckedContinuation<(URL, URLResponse), Error>) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // URLSession deletes the file after this method returns — copy to a safe location
        let safeCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: safeCopy)
            guard let response = downloadTask.response else {
                continuation.resume(throwing: URLError(.badServerResponse))
                return
            }
            continuation.resume(returning: (safeCopy, response))
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - UploadTransferDelegate

/// Bridges `URLSessionDataDelegate` completion to a `CheckedContinuation`.
/// Accumulates response data chunks and delivers the final result.
final class UploadTransferDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: CheckedContinuation<(Data, URLResponse), Error>
    private var responseData = Data()

    init(continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
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


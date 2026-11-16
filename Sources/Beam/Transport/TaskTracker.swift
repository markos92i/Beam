//
//  TaskTracker.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 19/9/24.
//

import Foundation
import Synchronization

/// The attempt's task delegate: URLSession's async API reports the task in `didCreateTask`.
final class TaskTracker: NSObject, URLSessionTaskDelegate, Sendable {
    private let progress: Progress
    private let state = Mutex<(task: URLSessionTask?, observation: NSKeyValueObservation?)>((nil, nil))

    init(progress: Progress) {
        self.progress = progress
    }

    var task: URLSessionTask? {
        state.withLock { $0.task }
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        track(task)
    }

    /// `.initial` seeds the current value; `.new` keeps firing as the task uploads, so the shared
    /// progress tracks the transfer instead of freezing at its starting fraction.
    func track(_ task: URLSessionTask) {
        let progress = self.progress
        // A task without a progress is still kept, to be cancelled.
        let observation = task.progressIfAny?.observe(\.fractionCompleted, options: [.initial, .new]) { _, _ in
            progress.follow(task)
        }
        let previous = state.withLock { state in
            defer { state = (task, observation) }
            return state.observation
        }
        previous?.invalidate()
    }

    /// Copies the task's last state: the last update may not have been observed yet.
    func finish() {
        let (task, observation) = state.withLock { $0 }
        observation?.invalidate()
        if let task { progress.follow(task) }
    }
}

// MARK: - Progress of a transfer

extension Progress {
    /// Scale while the body's size is still zero (a request not sent yet, a mocked task).
    static let transferUnits: Int64 = 1_000_000

    /// Copies the fraction: URLSession keeps the task's units at 5 of 100 and only `fractionCompleted` moves.
    func follow(_ task: URLSessionTask) {
        guard let taskProgress = task.progressIfAny else { return }
        let isUpload = task is URLSessionUploadTask
        if isUpload || task is URLSessionDownloadTask { describeFileTransfer(isUpload ? .uploading : .downloading) }
        let expected = isUpload ? task.countOfBytesExpectedToSend : task.countOfBytesExpectedToReceive
        follow(
            fraction: taskProgress.fractionCompleted,
            bytes: expected == NSURLSessionTransferSizeUnknown ? nil : expected,
            finished: task.state == .completed && task.error == nil
        )
    }

    /// Units are the body's bytes, so `localizedAdditionalDescription` reads "1,5 MB of 3 MB"; `nil` bytes is an unknown size.
    func follow(fraction: Double, bytes: Int64?, finished: Bool) {
        let units = bytes.map { $0 > 0 ? $0 : Self.transferUnits }
        if finished {
            totalUnitCount = units ?? Self.transferUnits
            completedUnitCount = totalUnitCount
        } else if let units {
            totalUnitCount = units
            completedUnitCount = Int64((min(max(fraction, 0), 1) * Double(units)).rounded(.down))
        } else {
            totalUnitCount = -1
            completedUnitCount = 0
        }
    }

    /// Lets the system describe the transfer ("Uploading files…") in the user's language.
    private func describeFileTransfer(_ operation: FileOperationKind) {
        guard kind != .file || fileOperationKind != operation else { return }
        kind = .file
        fileOperationKind = operation
    }
}

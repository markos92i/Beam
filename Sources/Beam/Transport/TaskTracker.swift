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

    /// `.initial`: the progress starts over with each task.
    func track(_ task: URLSessionTask) {
        let progress = self.progress
        // A task without a progress is still kept, to be cancelled.
        let observation = task.progressIfAny?.observe(\.fractionCompleted, options: [.initial]) { _, _ in
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
    /// A fixed scale, not bytes.
    static let transferUnits: Int64 = 1_000_000

    /// Copies the fraction: URLSession keeps the task's units at 5 of 100 and only `fractionCompleted` moves.
    func follow(_ task: URLSessionTask) {
        guard let taskProgress = task.progressIfAny else { return }
        let expected = task is URLSessionUploadTask ? task.countOfBytesExpectedToSend : task.countOfBytesExpectedToReceive
        follow(
            fraction: taskProgress.fractionCompleted,
            sizeKnown: expected != NSURLSessionTransferSizeUnknown,
            finished: task.state == .completed && task.error == nil
        )
    }

    func follow(fraction: Double, sizeKnown: Bool, finished: Bool) {
        if finished {
            totalUnitCount = Self.transferUnits
            completedUnitCount = Self.transferUnits
        } else if sizeKnown {
            totalUnitCount = Self.transferUnits
            completedUnitCount = Int64((min(max(fraction, 0), 1) * Double(Self.transferUnits)).rounded(.down))
        } else {
            totalUnitCount = -1
            completedUnitCount = 0
        }
    }
}

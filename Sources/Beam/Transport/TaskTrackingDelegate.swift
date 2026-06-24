//
//  TaskTrackingDelegate.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 19/9/24.
//

import Foundation

/// Task-level delegate that captures newly created tasks for progress tracking.
///
/// Passed as the `delegate` parameter to URLSession data/upload/download methods
/// so the Client can observe the task's `Progress` and expose it to callers.
final class TaskTrackingDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let onTaskCreated: (@Sendable (URLSessionTask) -> Void)?

    init(onTaskCreated: (@Sendable (URLSessionTask) -> Void)? = nil) {
        self.onTaskCreated = onTaskCreated
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        onTaskCreated?(task)
    }
}

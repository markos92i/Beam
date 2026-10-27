//
//  SessionDelegate.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 3/7/26.
//

import Foundation
import Logy
import Synchronization

/// The delegate of every Beam session: server trust, delegate-driven transfers and,
/// in a background session, the results nobody awaits.
public final class SessionDelegate: NSObject, Sendable {
    private let trustPolicy: (any TransportTrustPolicy)?
    let store: TransferStore?
    private let state = Mutex(State())

    /// Gets `nil` when the task's result was already handed out.
    typealias Waiter = CheckedContinuation<BackgroundTransferResult?, Never>

    private struct State {
        var uploadBodies: [Int: Data] = [:]
        /// More than one when a background `start(id:)` attaches to a task in flight.
        var waiters: [Int: [Waiter]] = [:]
        /// Result already handed out: a call that attaches later finds nothing to wait for.
        var finishedTasks: Set<Int> = []
        /// URLSession reports a trust rejection as `.cancelled`.
        var rejectedTrust: Set<Int> = []
        var listeners: [UUID: Listener] = [:]
        /// Events finished with no `.eventsDelivered` listener: the next one ends right away.
        var didFinishEvents = false
    }

    init(trustPolicy: (any TransportTrustPolicy)? = nil, store: TransferStore? = nil) {
        self.trustPolicy = trustPolicy
        self.store = store
    }

    /// A session serves many APIs, so it logs with the level of `LogSubsystem.beam`.
    private static let logger = BeamLogger()

    // MARK: - Waiting for a task

    /// `nil` when the result was already handed out: a task may finish just as a `start(id:)` attaches.
    func attach(to task: URLSessionTask) async -> BackgroundTransferResult? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (waiter: Waiter) in
                let waiting = state.withLock { state in
                    guard !state.finishedTasks.contains(task.taskIdentifier) else { return false }
                    state.waiters[task.taskIdentifier, default: []].append(waiter)
                    return true
                }
                if waiting { task.resume() } else { waiter.resume(returning: nil) }
            }
        } onCancel: {
            // Cancelling also works before `resume()`: URLSession still completes the task.
            task.cancel()
        }
    }

    func isFinished(_ task: URLSessionTask) -> Bool {
        state.withLock { $0.finishedTasks.contains(task.taskIdentifier) }
    }

    /// Takes the waiters and marks the task finished at once, so a later attach doesn't wait forever.
    private func takeWaiters(of taskID: Int) -> [Waiter]? {
        state.withLock { state in
            let waiters = state.waiters.removeValue(forKey: taskID)
            if waiters != nil { state.finishedTasks.insert(taskID) }
            return waiters
        }
    }

    /// Each call gets a file of its own: every call moves the one it gets.
    private func deliver(_ result: BackgroundTransferResult, to waiters: [Waiter]) {
        guard case .downloaded(let file) = result.outcome else {
            for waiter in waiters { waiter.resume(returning: result) }
            return
        }
        for (waiter, kept) in zip(waiters, Self.keep(file, count: waiters.count)) {
            var own = result
            own.outcome = .init(keeping: kept)
            waiter.resume(returning: own)
        }
    }

    // MARK: - Trust Rejections

    /// A cancellation caused by the trust policy becomes `.serverCertificateUntrusted`, not a user cancellation.
    func resolve(_ error: URLError, for task: URLSessionTask?) -> URLError {
        guard error.code == .cancelled, let task,
              state.withLock({ $0.rejectedTrust.remove(task.taskIdentifier) }) != nil else { return error }
        var userInfo = error.userInfo
        userInfo[NSLocalizedDescriptionKey] = "The server's certificate was rejected by the trust policy"
        return URLError(.serverCertificateUntrusted, userInfo: userInfo)
    }

    // MARK: - Results nobody awaits

    // Yielding and finishing under the lock keeps arrival order and makes subscribing atomic.

    struct Listener {
        let continuation: AsyncStream<BackgroundTransferResult>.Continuation
        let untilEventsDelivered: Bool
    }

    func listen(_ continuation: AsyncStream<BackgroundTransferResult>.Continuation, untilEventsDelivered: Bool) -> UUID {
        state.withLock { state in
            let id = UUID()
            if untilEventsDelivered, state.didFinishEvents {
                state.didFinishEvents = false
                continuation.finish()
            } else {
                state.listeners[id] = Listener(continuation: continuation, untilEventsDelivered: untilEventsDelivered)
            }
            return id
        }
    }

    func stopListening(_ id: UUID) {
        state.withLock { _ = $0.listeners.removeValue(forKey: id) }
    }

    /// Called after the result is kept: a call attaching before gets it here, one after takes it from the store.
    private func handOut(_ result: BackgroundTransferResult, of task: URLSessionTask) {
        let waiters = state.withLock { state in
            state.finishedTasks.insert(task.taskIdentifier)
            return state.waiters.removeValue(forKey: task.taskIdentifier)
        }
        guard let waiters else {
            Self.logFinished(result)
            state.withLock { state in
                for listener in state.listeners.values { listener.continuation.yield(result) }
            }
            return
        }
        // The late calls claim it, as a `start(id:)` claims a stored result.
        deliver(result, to: waiters)
        if let id = result.storeID { store?.remove(id) }
    }

    /// No call will log a transfer nobody awaits.
    private static func logFinished(_ result: BackgroundTransferResult) {
        let description = BackgroundTaskDescription(result.taskDescription)
        let failure: String? = if case .failed(let error) = result.outcome { error.logDescription } else { nil }
        logger.log(.backgroundFinished(
            id: description?.id ?? "?",
            method: description?.method ?? result.request?.httpMethod ?? "",
            path: description?.path ?? "",
            status: result.response?.statusCode,
            failure: failure
        ))
    }

    /// URLSession deletes `location` as soon as `didFinishDownloadingTo` returns.
    private static func keep(_ location: URL, count: Int) -> [Result<URL, TransportError>] {
        let first = FileUtils.temporaryLocation()
        do throws(FileError) {
            try FileUtils.move(location, to: first)
        } catch {
            return Array(repeating: .failure(.file(error)), count: count)
        }
        let copies = (1..<max(count, 1)).map { _ -> Result<URL, TransportError> in
            let copy = FileUtils.temporaryLocation()
            do throws(FileError) {
                try FileUtils.copy(first, to: copy)
                return .success(copy)
            } catch {
                return .failure(.file(error))
            }
        }
        return [.success(first)] + copies
    }
}

// MARK: - URLSessionDelegate

extension SessionDelegate: URLSessionDelegate {
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        state.withLock { state in
            let waiting = state.listeners.filter { $0.value.untilEventsDelivered }
            guard !waiting.isEmpty else {
                state.didFinishEvents = true
                return
            }
            for (id, listener) in waiting {
                listener.continuation.finish()
                state.listeners[id] = nil
            }
        }
    }
}

// MARK: - URLSessionTaskDelegate

extension SessionDelegate: URLSessionTaskDelegate {
    /// Per task (no session-level handler), to know which task a rejection belongs to.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trustPolicy else { return (.performDefaultHandling, nil) }

        let decision = trustPolicy.evaluate(challenge: challenge)
        if decision.0 == .cancelAuthenticationChallenge,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            state.withLock { _ = $0.rejectedTrust.insert(task.taskIdentifier) }
        }
        return decision
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let waiters = takeWaiters(of: task.taskIdentifier)
        let body = state.withLock { $0.uploadBodies.removeValue(forKey: task.taskIdentifier) } ?? Data()

        // A task of URLSession's async API: its call gets the error, and resolves it.
        if waiters == nil, task.delegate != nil {
            task.delegate?.urlSession?(session, task: task, didCompleteWithError: error)
            return
        }
        // URLSession's callback is untyped; it documents `URLError`.
        let urlError = error.map { resolve(URLError(bridging: $0), for: task) }

        if let waiters {
            // A finished download was handed out in didFinishDownloadingTo.
            let outcome: BackgroundTransferResult.Outcome = if let urlError {
                .failed(.network(urlError))
            } else if task is URLSessionDownloadTask {
                .failed(.network(URLError(.cannotParseResponse)))
            } else {
                .uploaded(body)
            }
            return deliver(BackgroundTransferResult(task: task, outcome: outcome), to: waiters)
        }

        // A cancellation isn't stored: the app cancelled it itself (e.g. on logout, after clearing the store).
        let result: BackgroundTransferResult
        if let urlError {
            let failed = BackgroundTransferResult(task: task, outcome: .failed(.network(urlError)))
            result = urlError.code == .cancelled ? failed : store?.saveFailure(of: task, urlError) ?? failed
        } else if task is URLSessionUploadTask {
            result = store?.save(body, ofUpload: task) ?? BackgroundTransferResult(task: task, outcome: .uploaded(body))
        } else {
            // A finished download was handled in didFinishDownloadingTo.
            return
        }
        handOut(result, of: task)
    }
}

// MARK: - URLSessionDownloadDelegate

extension SessionDelegate: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let waiters = takeWaiters(of: downloadTask.taskIdentifier) {
            return deliver(BackgroundTransferResult(task: downloadTask, outcome: .downloaded(location)), to: waiters)
        }
        // A task of URLSession's async API: its call gets the file.
        if let taskDelegate = downloadTask.delegate as? URLSessionDownloadDelegate {
            return taskDelegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
        }
        // Nobody waits: on disk in a background session, so it survives the process.
        let result = store?.save(location, of: downloadTask)
            ?? BackgroundTransferResult(task: downloadTask, outcome: .init(keeping: Self.keep(location, count: 1)[0]))
        handOut(result, of: downloadTask)
    }
}

// MARK: - URLSessionDataDelegate

extension SessionDelegate: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let taskDelegate = dataTask.delegate as? URLSessionDataDelegate
        // A task of URLSession's async API gets its data itself.
        let buffered = state.withLock { state in
            guard state.waiters[dataTask.taskIdentifier] != nil || taskDelegate == nil else { return false }
            state.uploadBodies[dataTask.taskIdentifier, default: Data()].append(data)
            return true
        }
        if !buffered {
            taskDelegate?.urlSession?(session, dataTask: dataTask, didReceive: data)
        }
    }
}

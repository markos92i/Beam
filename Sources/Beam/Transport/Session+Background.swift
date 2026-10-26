//
//  Session+Background.swift
//  Beam
//
//  What only a background session does: transfers that survive the app, attaching
//  to a transfer already in flight, and the results that arrive after a relaunch.
//

import Foundation

extension Session where Kind == Background {
    /// The background session identifier.
    public var identifier: String {
        urlSession.configuration.identifier ?? ""
    }

    // MARK: - Finished transfers

    /// Transfers that finished with nobody awaiting them: the stored ones oldest first, then new ones.
    /// Each stays on disk until ``remove(_:)`` or a `start(id:)` with the same id and route takes it.
    public func finished(until end: FinishedTransfer.Until = .cancelled) -> AsyncStream<FinishedTransfer> {
        // Listen before reading the store, so nothing in between is missed.
        let (live, liveContinuation) = AsyncStream<BackgroundTransferResult>.makeStream()
        let listening = sessionDelegate.listen(liveContinuation, untilEventsDelivered: end == .eventsDelivered)

        let (stream, continuation) = AsyncStream<FinishedTransfer>.makeStream()
        let task = Task(name: "Beam.Session.finished") { [self] in
            var handedOut: Set<String> = []
            if let store = sessionDelegate.store {
                for entry in store.entries() {
                    handedOut.insert(entry.id)
                    continuation.yield(finish(store.result(of: entry)))
                }
            }
            for await result in live {
                if let id = result.storeID, handedOut.contains(id) { continue }
                continuation.yield(finish(result))
            }
            continuation.finish()
        }
        continuation.onTermination = { [sessionDelegate] _ in
            task.cancel()
            sessionDelegate.stopListening(listening)
        }
        return stream
    }

    /// Removes a finished transfer and its file, if still there.
    public func remove(_ transfer: FinishedTransfer) {
        guard let id = transfer.storeID else { return }
        sessionDelegate.store?.remove(id)
    }

    /// Removes every finished transfer with its file, e.g. on logout.
    public func removeAllFinishedTransfers() {
        sessionDelegate.store?.removeAll()
    }

    // MARK: - Transfers (used by Client)

    func transfer(
        _ key: BackgroundTaskKey,
        track: @Sendable (URLSessionTask) -> Void,
        make: @Sendable () throws(FileError) -> URLSessionTask
    ) async throws(TransportError) -> BackgroundTransferResult {
        // A task can finish just as the call attaches: looking once more finds its result or makes a new task.
        for _ in 0..<2 {
            let transfer: BackgroundTransfer
            do { transfer = try await registry.transfer(key, pending: sessionDelegate, make: make) } catch { throw .file(error) }
            switch transfer {
            case .finished(let result):
                return result
            case .task(let task):
                track(task)
                if let result = await sessionDelegate.attach(to: task) { return result }
            }
        }
        throw .network(URLError(.badServerResponse))
    }

    // MARK: - Finishing

    func finish(_ result: BackgroundTransferResult) -> FinishedTransfer {
        let description = BackgroundTaskDescription(result.taskDescription)
        let response = result.response

        var body: Data?
        let outcome: FinishedTransfer.Outcome
        switch result.outcome {
        case .failed(let error):
            outcome = .failed(APIError(error))
        case .uploaded(let data):
            body = data
            outcome = Self.succeeded(response, .upload) ? .uploaded(data) : .failed(Self.httpError(response, body: data))
        case .downloaded(let url) where result.storeID != nil:
            // Kept in the store until the app removes it: nothing is moved or deleted.
            if Self.succeeded(response, .download) {
                outcome = .downloaded(url)
            } else {
                body = FileUtils.errorBody(at: url)
                outcome = .failed(Self.httpError(response, body: body))
            }
        case .downloaded(let url):
            if let response, Self.succeeded(response, .download) {
                do {
                    outcome = .downloaded(try FileUtils.store(url, for: response))
                } catch {
                    outcome = .failed(.storage(error))
                }
            } else {
                // The file is the server's error body.
                body = FileUtils.errorBody(at: url)
                FileUtils.discard(url)
                outcome = .failed(Self.httpError(response, body: body))
            }
        }

        return FinishedTransfer(
            id: description?.id,
            method: description.flatMap { HTTPMethod(rawValue: $0.method) },
            pathTemplate: description?.path,
            request: result.request?.withoutCredentials,
            response: response,
            body: body,
            outcome: outcome,
            storeID: result.storeID
        )
    }

    private static func succeeded(_ response: HTTPURLResponse?, _ operation: EndpointContext.Operation) -> Bool {
        response?.httpStatus.succeeds(for: operation) ?? false
    }

    private static func httpError(_ response: HTTPURLResponse?, body: Data?) -> APIError<Void> {
        guard let response else { return .transport(.network(URLError(.badServerResponse))) }
        return .http(status: response.httpStatus, body: HTTPErrorBody(data: body), response: response)
    }
}

// MARK: - BackgroundTransfer

enum BackgroundTransfer: Sendable {
    case task(URLSessionTask)
    case finished(BackgroundTransferResult)
}

// MARK: - Task description

/// Stored in `taskDescription`, which survives a relaunch, to recognise the task.
struct BackgroundTaskDescription: Codable, Sendable {
    let v: Int
    let id: String
    let method: String
    let path: String

    init(_ key: BackgroundTaskKey) {
        self.v = 1
        self.id = key.id
        self.method = key.method
        self.path = key.path
    }

    init?(_ string: String?) {
        guard let data = string?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data),
              decoded.v == 1 else { return nil }
        self = decoded
    }

    var encoded: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? id
    }

    var key: BackgroundTaskKey {
        BackgroundTaskKey(id: id, method: method, path: path)
    }
}

struct BackgroundTaskKey: Hashable, Sendable {
    let id: String
    let method: String
    let path: String
}

extension APIRequest {
    func backgroundKey(_ id: String) -> BackgroundTaskKey {
        BackgroundTaskKey(id: id, method: method.rawValue, path: pathTemplate)
    }
}

// MARK: - Registry

/// Attaches a `start(id:)` to the task in flight with its key instead of starting a duplicate.
actor BackgroundTaskRegistry {
    private let session: URLSession
    private var tasks: [BackgroundTaskKey: URLSessionTask] = [:]
    private var reconnection: Task<[URLSessionTask], Never>?
    private var reconnected = false

    init(session: URLSession) {
        self.session = session
    }

    func transfer(
        _ key: BackgroundTaskKey,
        pending: SessionDelegate,
        make: @Sendable () throws(FileError) -> URLSessionTask
    ) async throws(FileError) -> BackgroundTransfer {
        await reconnect()

        // A task can still be running with its result already handed out.
        if let task = tasks[key], task.isInFlight, !pending.isFinished(task) {
            return .task(task)
        }
        if let result = pending.store?.take(key) {
            tasks[key] = nil
            return .finished(result)
        }
        let task = try make()
        // To recognise it after a relaunch.
        task.taskDescription = BackgroundTaskDescription(key).encoded
        tasks[key] = task
        return .task(task)
    }

    /// Reconnects once with the tasks left by a previous launch; concurrent first calls share the load.
    private func reconnect() async {
        guard !reconnected else { return }
        let session = self.session
        let reconnection = self.reconnection ?? Task { await session.allTasks }
        self.reconnection = reconnection
        let existing = await reconnection.value
        guard !reconnected else { return }
        reconnected = true
        for task in existing where task.isInFlight {
            guard let key = BackgroundTaskDescription(task.taskDescription)?.key, tasks[key] == nil else { continue }
            tasks[key] = task
        }
    }
}

private extension URLSessionTask {
    var isInFlight: Bool { state == .running || state == .suspended }
}

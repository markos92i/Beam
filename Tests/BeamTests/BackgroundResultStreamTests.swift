//
//  BackgroundResultStreamTests.swift
//  Beam
//
//  `Session<Background>.finished(until:)`: the stream's semantics, driven with the same
//  callbacks URLSession uses for transfers that finish with no waiter (background
//  relaunch), and how unclaimed results are validated. No network.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// Background sessions live for the process: releasing them while other tests run
// real background transfers disturbs those. One static session per test.
private func makeSession() -> Session<Background> {
    Session(.background("com.beam.test.results.\(UUID().uuidString)")) { $0.sessionSendsLaunchEvents = false }
}

private enum Sessions {
    static let accumulated = makeSession()
    static let late = makeSession()
    static let replaced = makeSession()
    static let kept = makeSession()
    static let cycles = makeSession()
    static let attaching = makeSession()
    static let reattaching = makeSession()
    static let validation = makeSession()
}

@Suite
struct BackgroundResultStreamTests {

    // MARK: - Helpers

    /// Simulates URLSession reporting a download that failed with nobody awaiting it.
    private func deliver(_ name: String, to session: Session<Background>) {
        let task = URLSession.shared.downloadTask(with: URL(string: "https://example.invalid/\(name)")!) // never resumed
        session.sessionDelegate.urlSession(URLSession.shared, task: task, didCompleteWithError: URLError(.timedOut))
    }

    private func finishEvents(of session: Session<Background>) {
        session.sessionDelegate.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
    }

    /// Consumes `stream` in the background so results can be inspected while it runs.
    private final class Collector: Sendable {
        private final class Storage: Sendable {
            let value = Mutex<(names: [String], transfers: [FinishedTransfer], finished: Bool)>(([], [], false))
        }

        private let storage = Storage()
        private let task: Task<Void, Never>

        init(_ stream: AsyncStream<FinishedTransfer>) {
            let storage = self.storage
            task = Task {
                for await transfer in stream {
                    storage.value.withLock {
                        $0.names.append(transfer.request?.url?.lastPathComponent ?? "?")
                        $0.transfers.append(transfer)
                    }
                }
                if !Task.isCancelled { storage.value.withLock { $0.finished = true } }
            }
        }

        var names: [String] { storage.value.withLock { $0.names } }
        var transfers: [FinishedTransfer] { storage.value.withLock { $0.transfers } }
        var finished: Bool { storage.value.withLock { $0.finished } }

        /// Waits until `condition` holds or the limit elapses.
        func wait(upTo limit: Duration = .seconds(2), until condition: (Collector) -> Bool) async {
            let deadline = ContinuousClock.now + limit
            while !condition(self), ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        func stop() { task.cancel() }
    }

    // MARK: - Stream

    @Test
    func handsOutStoredThenLiveResultsAndFinishesWhenEventsAreDelivered() async {
        let session = Sessions.accumulated
        defer { session.removeAllFinishedTransfers() }
        deliver("a", to: session)
        deliver("b", to: session)

        let collector = Collector(session.finished(until: .eventsDelivered))
        await collector.wait { $0.names.count == 2 }
        deliver("c", to: session)
        await collector.wait { $0.names.count == 3 }
        finishEvents(of: session)

        await collector.wait { $0.finished }
        #expect(collector.names == ["a", "b", "c"])
        #expect(collector.finished)
    }

    /// Receiving a transfer doesn't remove it: a later stream — a later launch — gets it
    /// again, until the app removes it.
    @Test
    func aTransferIsHandedOutAgainUntilRemoved() async throws {
        let session = Sessions.kept
        defer { session.removeAllFinishedTransfers() }
        deliver("kept", to: session)
        deliver("handled", to: session)

        let first = Collector(session.finished())
        await first.wait { $0.names.count == 2 }
        first.stop()
        session.remove(try #require(first.transfers.first { $0.request?.url?.lastPathComponent == "handled" }))

        let second = Collector(session.finished())
        defer { second.stop() }
        await second.wait { $0.names.count == 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(second.names == ["kept"])
    }

    /// Nothing is consumed, so any number of streams listen at once: the app's
    /// `.backgroundTask` and the screen that started the transfer.
    @Test
    func severalStreamsGetTheSameResults() async {
        let session = Sessions.replaced
        defer { session.removeAllFinishedTransfers() }
        let first = Collector(session.finished())
        let second = Collector(session.finished())
        defer { first.stop(); second.stop() }
        try? await Task.sleep(for: .milliseconds(50)) // let both listen

        deliver("x", to: session)

        await first.wait { $0.names.count == 1 }
        await second.wait { $0.names.count == 1 }
        #expect(first.names == ["x"])
        #expect(second.names == ["x"])
        #expect(!first.finished && !second.finished)
    }

    /// Regression: if the session finished delivering events before the stream was
    /// created, `for await` over it never ended.
    @Test
    func aStreamCreatedAfterEventsWereDeliveredStillEnds() async {
        let session = Sessions.late
        defer { session.removeAllFinishedTransfers() }
        deliver("late", to: session)
        finishEvents(of: session)

        let collector = Collector(session.finished(until: .eventsDelivered))
        await collector.wait { $0.finished }
        defer { collector.stop() }

        #expect(collector.names == ["late"])
        #expect(collector.finished)
    }

    @Test
    func deliveringEventsDoesNotEndALaterCycleNorAStreamUntilCancelled() async {
        let session = Sessions.cycles
        defer { session.removeAllFinishedTransfers() }
        let screen = Collector(session.finished())
        defer { screen.stop() }
        finishEvents(of: session)

        // The first `.eventsDelivered` stream ends right away...
        let first = Collector(session.finished(until: .eventsDelivered))
        await first.wait { $0.finished }
        #expect(first.finished)

        // ...but that is consumed: the next one stays open for new events, and so does
        // the stream that ends only when cancelled.
        let second = Collector(session.finished(until: .eventsDelivered))
        defer { second.stop() }
        deliver("next", to: session)
        await second.wait { $0.names.count == 1 }
        await screen.wait { $0.names.count == 1 }
        #expect(second.names == ["next"])
        #expect(!second.finished)
        #expect(screen.names == ["next"])
        #expect(!screen.finished)
    }

    // MARK: - Attaching to a transfer that just finished

    /// A download task of `session` that "finishes" through the delegate callbacks
    /// URLSession uses, without ever running: no waiter, so its result is kept.
    private func finishedDownloadTask(_ path: String, id: String, on session: Session<Background>) async throws -> URLSessionDownloadTask {
        let key = BackgroundTaskKey(id: id, method: "GET", path: path)
        let request = URLRequest(url: URL(string: "https://postman-echo.com\(path)")!)
        guard case .task(let created) = try await session.registry.transfer(key, pending: session.sessionDelegate, make: { () throws(FileError) in
            session.makeDownloadTask(request, key: key)
        }), let task = created as? URLSessionDownloadTask else {
            Issue.record("Expected a new task")
            throw CancellationError()
        }
        let location = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("done".utf8).write(to: location)
        session.sessionDelegate.urlSession(session.urlSession, downloadTask: task, didFinishDownloadingTo: location)
        session.sessionDelegate.urlSession(session.urlSession, task: task, didCompleteWithError: nil)
        return task
    }

    /// Regression: a call attaching to a task whose result was just handed out waited for
    /// callbacks that had already happened, forever. Now it learns there is nothing to wait for.
    @Test(.timeLimit(.minutes(1)))
    func waitingForATaskThatAlreadyFinishedReturnsAtOnce() async throws {
        let session = Sessions.attaching
        defer { session.removeAllFinishedTransfers() }
        let task = try await finishedDownloadTask("/get", id: "finished", on: session)

        #expect(await session.sessionDelegate.attach(to: task) == nil)
        #expect(task.state == .suspended, "It resumed the task instead of seeing it had finished")
    }

    /// A call attaching to a task whose waiters already got its result — URLSession may
    /// still report it running — learns at once that there is nothing to wait for.
    @Test(.timeLimit(.minutes(1)))
    func attachingAfterTheWaitersGotTheResultReturnsAtOnce() async throws {
        let delegate = SessionDelegate()
        let task = URLSession(configuration: .ephemeral).uploadTask(with: URLRequest(url: URL(string: "https://mock.invalid")!), from: Data())
        let waiting = Task { await delegate.attach(to: task) }
        // It resumes the task once it waits for it.
        while task.state == .suspended { try await Task.sleep(for: .milliseconds(5)) }
        delegate.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)

        #expect(await waiting.value != nil)
        #expect(await delegate.attach(to: task) == nil)
    }

    /// A `start(id:)` that finds the task still "running" but already finished takes the
    /// kept result instead of waiting on it — or restarting it.
    @Test(.timeLimit(.minutes(1)))
    func startingAgainOnATaskThatJustFinishedTakesItsKeptResult() async throws {
        let session = Sessions.reattaching
        defer { session.removeAllFinishedTransfers() }
        let task = try await finishedDownloadTask("/get", id: "just-finished", on: session)
        #expect(session.sessionDelegate.store?.entries().count == 1)

        let endpoint = Endpoint<URL, Void>(config: RequestConfig(retry: .none), api: APIRequest(method: .get, host: "https://postman-echo.com", path: "/get", pathTemplate: "/get"))
        do {
            _ = try await endpoint.backgroundDownloadTask(on: session).start(id: "just-finished")
            Issue.record("Expected the kept result, which has no response in this simulation")
        } catch {
            // The simulated task never got a response: the kept result says so.
            #expect(error == .noResponse)
        }
        #expect(task.state == .suspended, "It waited on — and resumed — the finished task")
        #expect(session.sessionDelegate.store?.entries().isEmpty == true)
    }

    // MARK: - Validation and reporting

    private static let key = BackgroundTaskKey(id: "video-42", method: "POST", path: "/{userID}/documents")

    private func result(
        status: Int?,
        _ outcome: BackgroundTransferResult.Outcome,
        description: String? = BackgroundTaskDescription(key).encoded
    ) -> BackgroundTransferResult {
        let url = URL(string: "https://api.example.com/7/documents")!
        return BackgroundTransferResult(
            request: URLRequest(url: url),
            taskDescription: description,
            response: status.map { HTTPURLResponse(url: url, statusCode: $0, httpVersion: nil, headerFields: ["Content-Type": "application/json"])! },
            outcome: outcome
        )
    }

    @Test
    func aSuccessfulUploadCarriesItsIDRouteAndBody() throws {
        let body = json(ResponseMock(id: "doc", value: 1))
        let finished = Sessions.validation.finish(result(status: 201, .uploaded(body)))

        #expect(finished.id == "video-42")
        #expect(finished.method == .post)
        #expect(finished.pathTemplate == "/{userID}/documents")
        guard case .uploaded(let data) = finished.outcome else {
            Issue.record("Expected an upload, got \(finished.outcome)")
            return
        }
        #expect(data == body)
        #expect(try finished.decode(ResponseMock.self, json: .default).id == "doc")
    }

    @Test
    func anHTTPErrorIsAFailureThatKeepsTheErrorBody() throws {
        let body = json(ResponseMock(id: "E500", value: 0))
        let finished = Sessions.validation.finish(result(status: 500, .uploaded(body)))

        guard case .failed(let error) = finished.outcome else {
            Issue.record("Expected a failure, got \(finished.outcome)")
            return
        }
        #expect(error == .http(status: .internalServerError))
        #expect(error.response?.statusCode == 500)
        #expect(try finished.decode(ResponseMock.self, json: .default).id == "E500")
    }

    @Test
    func aTransportFailureKeepsItsKind() {
        let finished = Sessions.validation.finish(result(status: nil, .failed(.network(URLError(.notConnectedToInternet)))))
        guard case .failed(let error) = finished.outcome else {
            Issue.record("Expected a failure")
            return
        }
        #expect(error == .noConnection)
    }

    @Test
    func aSuccessfulDownloadIsStoredInCaches() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: file)
        let finished = Sessions.validation.finish(result(status: 200, .downloaded(file)))

        guard case .downloaded(let stored) = finished.outcome else {
            Issue.record("Expected a download, got \(finished.outcome)")
            return
        }
        defer { try? FileManager.default.removeItem(at: stored.deletingLastPathComponent()) }
        // In a folder of its own inside caches, moved — not copied — from where it was.
        let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        #expect(stored.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == caches.standardizedFileURL)
        #expect(try Data(contentsOf: stored) == Data("{}".utf8))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func aFailedDownloadKeepsTheErrorBodyAndRemovesTheFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try json(ResponseMock(id: "E404", value: 0)).write(to: file)
        let finished = Sessions.validation.finish(result(status: 404, .downloaded(file)))

        #expect(try finished.decode(ResponseMock.self, json: .default).id == "E404")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func aResultDecodesWithAnyBodyDecoder() throws {
        let finished = Sessions.validation.finish(result(status: 201, .uploaded(Data("created".utf8))))
        #expect(try finished.decode(using: .text, json: .default) == "created")
        #expect(try finished.decode(using: .data, json: .default) == Data("created".utf8))
    }

    @Test
    func aTaskBeamDidNotCreateHasNoID() {
        let finished = Sessions.validation.finish(result(status: 200, .uploaded(Data()), description: "someone else's"))
        #expect(finished.id == nil)
        #expect(finished.method == nil)
    }

    // MARK: - Task description

    @Test
    func theTaskDescriptionRoundTrips() {
        let decoded = BackgroundTaskDescription(BackgroundTaskDescription(Self.key).encoded)
        #expect(decoded?.key == Self.key)
    }

    @Test
    func foreignTaskDescriptionsAreIgnored() {
        #expect(BackgroundTaskDescription("video-42") == nil)
        #expect(BackgroundTaskDescription(#"{"v":2,"id":"x","method":"GET","path":"/"}"#) == nil)
        #expect(BackgroundTaskDescription(nil) == nil)
    }
}

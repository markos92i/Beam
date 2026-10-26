//
//  CallStateTests.swift
//  Beam
//
//  Every call has its own state — id, progress, cancellation, resume data — kept by
//  its `Client`. An endpoint holds none, so calls on the same endpoint don't mix.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Fixtures

/// Reports each request's task through the task delegate, as `URLSession` does, with
/// a progress of 10 of 10 units. Each request then answers after `wait`, or fails at
/// once if its task is cancelled first.
private final class TrackingSession: SessionProtocol {
    let sessionDelegate = SessionDelegate()
    private let wait: Duration

    init(wait: Duration = .zero) {
        self.wait = wait
    }

    private func respond(_ request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        let task = URLSession.shared.dataTask(with: request) // never resumed: no network
        delegate?.urlSession?(URLSession.shared, didCreateTask: task)
        task.progress.totalUnitCount = 10
        task.progress.completedUnitCount = 10

        let deadline = ContinuousClock.now + wait
        repeat {
            if task.state == .canceling || task.state == .completed { throw URLError(.cancelled) }
            do { try await Task.sleep(for: .milliseconds(10)) } catch { throw URLError(.cancelled) }
        } while ContinuousClock.now < deadline

        let body = Data(#"{"id":"1","value":1}"#.utf8)
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        try await respond(request, delegate: delegate)
    }

    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        try await respond(request, delegate: delegate)
    }

    // Unused by these tests.
    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URLSession.AsyncBytes, URLResponse) { throw URLError(.unsupportedURL) }
    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { throw URLError(.unsupportedURL) }
    func download(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { throw URLError(.unsupportedURL) }
    func upload(for: URLRequest, fromFile: URL, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { throw URLError(.unsupportedURL) }
    func downloadTask(with request: URLRequest) -> URLSessionDownloadTask { URLSession.shared.downloadTask(with: request) }
    func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask { URLSession.shared.downloadTask(withResumeData: data) }
    func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask { URLSession.shared.uploadTask(with: request, from: data) }
    func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask { URLSession.shared.uploadTask(with: request, fromFile: url) }
    func uploadTask(withResumeData data: Data) -> URLSessionUploadTask { URLSession.shared.uploadTask(withResumeData: data) }
    func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask { URLSession.shared.webSocketTask(with: request) }
}

/// Reports progress as URLSession does: the task's own units stay at 5 of 100 (the
/// request) and the body advances an internal child worth the other 95. Each attempt
/// calls `atStart` right after reporting its task, then `halfway` with the body half
/// sent, then answers — or, with `failFirst`, the first attempt fails there.
private final class ChildProgressSession: SessionProtocol {
    let sessionDelegate = SessionDelegate()
    private let failFirst: Bool
    private let atStart: @Sendable () -> Void
    private let halfway: @Sendable (URLSessionTask) async -> Void
    private let attempts = Mutex(0)

    init(failFirst: Bool = false, atStart: @escaping @Sendable () -> Void = {}, halfway: @escaping @Sendable (URLSessionTask) async -> Void) {
        self.failFirst = failFirst
        self.atStart = atStart
        self.halfway = halfway
    }

    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        let attempt = attempts.withLock { $0 += 1; return $0 }
        let task = URLSession.shared.dataTask(with: request) // never resumed: no network
        delegate?.urlSession?(URLSession.shared, didCreateTask: task)
        atStart()

        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = 5
        let body = Progress(totalUnitCount: 1000)
        task.progress.addChild(body, withPendingUnitCount: 95)
        body.completedUnitCount = 500
        await halfway(task)

        if failFirst, attempt == 1 { throw URLError(.timedOut) }
        body.completedUnitCount = 1000
        let data = Data(#"{"id":"1","value":1}"#.utf8)
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    // Unused by these tests.
    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URLSession.AsyncBytes, URLResponse) { throw URLError(.unsupportedURL) }
    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { throw URLError(.unsupportedURL) }
    func download(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { throw URLError(.unsupportedURL) }
    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { throw URLError(.unsupportedURL) }
    func upload(for: URLRequest, fromFile: URL, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { throw URLError(.unsupportedURL) }
    func downloadTask(with request: URLRequest) -> URLSessionDownloadTask { URLSession.shared.downloadTask(with: request) }
    func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask { URLSession.shared.downloadTask(withResumeData: data) }
    func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask { URLSession.shared.uploadTask(with: request, from: data) }
    func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask { URLSession.shared.uploadTask(with: request, fromFile: url) }
    func uploadTask(withResumeData data: Data) -> URLSessionUploadTask { URLSession.shared.uploadTask(withResumeData: data) }
    func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask { URLSession.shared.webSocketTask(with: request) }
}

private func endpoint(_ session: any SessionProtocol) -> Endpoint<ResponseMock, Void> {
    Endpoint<ResponseMock, Void>(
        session: session,
        config: RequestConfig(retry: .none),
        api: APIRequest(method: .get, host: "https://base-url.com", path: "/items")
    )
}

/// Waits until `progress` passes `fraction`. A parent `Progress` may hear of a
/// child's change a moment later, so the check polls; one second is far more than
/// that delay, and a progress that never moves still fails the test.
private func waitForProgress(_ progress: Progress, toPass fraction: Double) async {
    let deadline = ContinuousClock.now + .seconds(1)
    while progress.fractionCompleted <= fraction, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// Runs `call` in a task, returning how it ended.
private func run(_ call: @escaping @Sendable () async throws(APIError<Void>) -> ResponseMock) -> Task<Result<ResponseMock, APIError<Void>>, Never> {
    Task {
        do throws(APIError<Void>) { return .success(try await call()) } catch { return .failure(error) }
    }
}

// MARK: - Tests

@Suite
struct CallStateTests {

    /// The calls used to share the endpoint's state: cancelling cancelled only the
    /// last call started, and the other went on.
    @Test
    func callsOnTheSameEndpointAreCancelledSeparately() async throws {
        // Long enough that a call that isn't cancelled is still running when checked.
        let wait = Duration.seconds(2)
        let shared = endpoint(TrackingSession(wait: wait))
        let first = shared.call()
        let second = shared.call()

        let firstCall = run { () throws(APIError<Void>) in try await first.client.run { () throws(APIError<Void>) in try await first.data() } }
        let secondCall = run { () throws(APIError<Void>) in try await second.client.run { () throws(APIError<Void>) in try await second.data() } }
        try await Task.sleep(for: .milliseconds(100))

        let clock = ContinuousClock()
        let start = clock.now
        await first.client.cancel()
        let firstResult = await firstCall.value
        #expect(clock.now - start < wait, "The cancelled call wasn't cut short")
        let secondResult = await secondCall.value

        guard case .failure(let error) = firstResult else {
            Issue.record("The cancelled call succeeded")
            return
        }
        #expect(error == .cancelled)
        #expect(try secondResult.get().id == "1")
    }

    @Test
    func eachCallHasItsOwnIdAndProgress() {
        let shared = endpoint(TrackingSession())
        let one = shared.call()
        let other = shared.call()

        #expect(one.id != other.id)
        #expect(one.client.progress !== other.client.progress)
    }

    @Test
    func theClientFollowsTheProgressOfItsCall() async throws {
        let call = endpoint(TrackingSession()).call()
        _ = try await call.data()

        #expect(call.client.progress.fractionCompleted == 1)
    }

    // MARK: Live progress

    /// URLSession keeps a task's units at 5 of 100 and advances an internal child
    /// progress, so only the fraction moves. The control used to copy the units and
    /// stayed at 5 % until the end.
    @Test
    func theProgressMovesWhileTheTransferRuns() async throws {
        let progress = Mutex<Progress?>(nil)
        let seen = Mutex<[Double]>([])
        let session = ChildProgressSession { _ in
            let followed = progress.withLock { $0 }!
            await waitForProgress(followed, toPass: 0.5)
            seen.withLock { $0.append(followed.fractionCompleted) }
        }
        let call = endpoint(session).call()
        progress.withLock { $0 = call.client.progress }
        _ = try await call.data()

        // Halfway through the body: 5 % for the request + half of the other 95 %.
        let halfway = try #require(seen.withLock { $0 }.first)
        #expect(abs(halfway - 0.525) < 0.001, "Progress during the transfer: \(halfway)")
        #expect(call.client.progress.fractionCompleted == 1)
    }

    @Test
    func everyAttemptStartsTheProgressOverFromZero() async throws {
        let progress = Mutex<Progress?>(nil)
        let atStart = Mutex<[Double]>([])
        let session = ChildProgressSession(failFirst: true, atStart: {
            let followed = progress.withLock { $0 }!
            atStart.withLock { $0.append(followed.fractionCompleted) }
        }) { _ in
            await waitForProgress(progress.withLock { $0 }!, toPass: 0.5)
        }
        let retrying = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: .linear(delay: .zero, maxAttempts: 1)),
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/items")
        )
        let call = retrying.call()
        progress.withLock { $0 = call.client.progress }
        _ = try await call.data()

        // The first attempt failed halfway; the second one started from zero.
        #expect(atStart.withLock { $0 } == [0, 0])
    }

    @Test
    func anUnknownSizeIsIndeterminate() {
        let progress = Progress()
        progress.follow(fraction: 0.05, sizeKnown: false, finished: false)
        #expect(progress.isIndeterminate)

        progress.follow(fraction: 0.05, sizeKnown: false, finished: true)
        #expect(!progress.isIndeterminate)
        #expect(progress.fractionCompleted == 1)
    }

    @Test
    func theFractionUsesAFixedScale() {
        let progress = Progress()
        progress.follow(fraction: 0.25, sizeKnown: true, finished: false)
        #expect(progress.totalUnitCount == Progress.transferUnits)
        #expect(progress.fractionCompleted == 0.25)
    }

    /// `onProgress` gets the progress of the transfer it reports, not one of its own.
    @Test
    func onProgressFollowsTheTransfer() async throws {
        let reported = Mutex<Progress?>(nil)
        _ = try await TestAPIClient(session: TrackingSession())
            .upload(body: UploadRequestMock(content: "Dummy"), onProgress: { progress in reported.withLock { $0 = progress } })

        let progress = try #require(reported.withLock { $0 })
        #expect(progress.fractionCompleted == 1)
    }

    /// Two handles from the same endpoint used to share its id and cancellation.
    @Test
    func handlesFromTheSameEndpointAreIndependent() {
        let shared = endpoint(TrackingSession())
        let one = shared.uploadTask(.body(.data(Data())))
        let other = shared.uploadTask(.body(.data(Data())))

        #expect(one.id != other.id)
        #expect(one.progress !== other.progress)
    }
}

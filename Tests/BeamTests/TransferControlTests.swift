//
//  TransferControlTests.swift
//  Beam
//
//  Cancellation, resume data and resumed retries of uploads and downloads, on both
//  paths: URLSession's native async API and delegate-driven tasks (handles).
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Fixtures

private let host = "https://base-url.com"

private func created(_ request: URLRequest, status: Int = 201) -> (Data, URLResponse) {
    (json(ResponseMock(id: "1", value: 1)), HTTPURLResponse(url: request.url ?? URL(string: host)!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}

private func uploadEndpoint(
    session: any SessionProtocol,
    retry: RetryPolicy = .none,
    auth: (any AuthProtocol)? = nil
) -> Endpoint<ResponseMock, Void> {
    Endpoint<ResponseMock, Void>(
        session: session,
        auth: auth,
        config: RequestConfig(retry: retry),
        api: APIRequest(method: .post, host: host, path: "/upload")
    )
}

/// What the upload endpoints upload.
private let dummy = UploadContent.body(.json(UploadRequestMock(content: "Dummy")))

/// Polls `condition` until it holds or `limit` elapses.
private func waitUntil(upTo limit: Duration = .seconds(2), _ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + limit
    while await !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Signs every request with a token that changes after each invalidation.
private final class RotatingAuth: AuthProtocol {
    let generation = Mutex(1)

    func authenticate(request: inout URLRequest) async throws(AuthError) {
        request.setValue("Bearer \(generation.withLock { $0 })", forHTTPHeaderField: "Authorization")
    }

    func invalidate() async {
        generation.withLock { $0 += 1 }
    }
}

// MARK: - Cancelling a handle

@Suite
struct HandleCancellationTests {

    /// Cancelling during the wait before a retry used to do nothing: no task was in
    /// flight, so the next attempt started anyway.
    @Test
    func cancelDuringTheBackoffStopsTheCall() async throws {
        let attempts = AtomicCounter()
        let session = MockSession({ (_) throws(URLError) in
            await attempts.increment()
            throw URLError(.timedOut)
        })
        let handle = uploadEndpoint(session: session, retry: .linear(delay: .seconds(30), maxAttempts: 3)).uploadTask(dummy)

        let job = Task { () -> Result<ResponseMock, APIError<Void>> in
            do throws(APIError<Void>) { return .success(try await handle.start()) } catch { return .failure(error) }
        }
        try await waitUntil { await attempts.value == 1 }

        let clock = ContinuousClock()
        let start = clock.now
        await handle.cancel()
        let result = await job.value

        #expect(clock.now - start < .seconds(2), "The backoff wasn't cut short")
        guard case .failure(let error) = result else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(error == .cancelled)
        #expect(await attempts.value == 1)
    }

    @Test
    func cancellingTheCallingTaskCancelsAHandleTransfer() async throws {
        let session = MockSession({ (request) throws(URLError) in created(request) }, delay: 30)
        let handle = uploadEndpoint(session: session).uploadTask(dummy)

        let job = Task { () -> Result<ResponseMock, APIError<Void>> in
            do throws(APIError<Void>) { return .success(try await handle.start()) } catch { return .failure(error) }
        }
        try await Task.sleep(for: .milliseconds(100))

        let clock = ContinuousClock()
        let start = clock.now
        job.cancel()
        let result = await job.value

        #expect(clock.now - start < .seconds(2))
        guard case .failure(let error) = result else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(error == .cancelled)
    }

    @Test
    func aHandleCanStartAgainAfterBeingCancelled() async throws {
        let session = MockSession({ (request) throws(URLError) in created(request) })
        let handle = uploadEndpoint(session: session).uploadTask(dummy)

        await handle.cancel() // nothing in flight
        let result = try await handle.start()
        #expect(result.id == "1")
    }
}

// MARK: - Resume data after a failure

@Suite
struct ResumeDataAfterFailureTests {

    @Test
    func aFailedHandleUploadKeepsItsResumeData() async {
        let resumeData = Data("upload-resume".utf8)
        let session = MockSession({ (_) throws(URLError) in
            throw URLError(.networkConnectionLost, userInfo: [NSURLSessionUploadTaskResumeData: resumeData])
        })
        let handle = uploadEndpoint(session: session).uploadTask(dummy)

        do {
            _ = try await handle.start()
            Issue.record("Expected the upload to fail")
        } catch {
            #expect(error == .noConnection)
        }
        // What the app does after a failure: ask the handle for the resume data.
        #expect(await handle.cancel() == resumeData)
        // It is handed out once.
        #expect(await handle.cancel() == nil)
    }

    @Test
    func aFailedDirectDownloadKeepsItsResumeData() async {
        let resumeData = Data("download-resume".utf8)
        let session = MockSession({ (_) throws(URLError) in
            throw URLError(.networkConnectionLost, userInfo: [NSURLSessionDownloadTaskResumeData: resumeData])
        })
        let endpoint = Endpoint<URL, Void>(
            session: session,
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: host, path: "/file")
        )

        let call = endpoint.call()
        _ = try? await call.download(resumeFrom: nil)
        #expect(await call.client.cancel() == resumeData)
    }

    @Test
    func startingAgainForgetsThePreviousResumeData() async throws {
        let failing = Mutex(true)
        let session = MockSession({ (request) throws(URLError) in
            if failing.withLock({ $0 }) {
                throw URLError(.networkConnectionLost, userInfo: [NSURLSessionUploadTaskResumeData: Data("old".utf8)])
            }
            return created(request)
        })
        let handle = uploadEndpoint(session: session).uploadTask(dummy)

        _ = try? await handle.start()
        failing.withLock { $0 = false }
        _ = try await handle.start()
        #expect(await handle.cancel() == nil)
    }
}

// MARK: - Resumed calls

@Suite
struct ResumedCallTests {

    @Test
    func aHandleResumesThroughTheDelegateDrivenPath() async throws {
        let resumeData = Data("resume".utf8)
        let resumed = Mutex<[Data]>([])
        let session = MockSession(uploadResume: { (data) throws(URLError) in
            resumed.withLock { $0.append(data) }
            return created(URLRequest(url: URL(string: host)!))
        })
        let handle = uploadEndpoint(session: session).uploadTask(dummy)

        _ = try await handle.start(resumeFrom: resumeData)
        #expect(resumed.withLock { $0 } == [resumeData])
    }

    /// The resume data carries the request it was created with — and its expired
    /// token. After the 401 refresh, the retry must start over with a request signed
    /// with the new credentials.
    @Test
    func a401OnAResumedUploadRetriesFromScratchWithFreshCredentials() async throws {
        let auth = RotatingAuth()
        let resumedAttempts = AtomicCounter()
        let freshTokens = Mutex<[String?]>([])
        let session = MockSession(
            { (request) throws(URLError) in
                freshTokens.withLock { $0.append(request.value(forHTTPHeaderField: "Authorization")) }
                return created(request)
            },
            { (_) throws(URLError) in
                await resumedAttempts.increment()
                return created(URLRequest(url: URL(string: host)!), status: 401)
            }
        )
        let handle = uploadEndpoint(session: session, auth: auth).uploadTask(dummy)

        let result = try await handle.start(resumeFrom: Data("resume".utf8))

        #expect(result.id == "1")
        #expect(await resumedAttempts.value == 1)
        #expect(freshTokens.withLock { $0 } == ["Bearer 2"])
    }

    /// When resuming fails, the retry uploads the content again — also a file, which
    /// the request's body never was.
    @Test
    func aFailedResumeOfAFileUploadUploadsTheFileAgain() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        try Data("file".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let resumedAttempts = AtomicCounter()
        let freshAttempts = AtomicCounter()
        let session = MockSession(
            { (request) throws(URLError) in
                await freshAttempts.increment()
                return created(request)
            },
            { (_) throws(URLError) in
                await resumedAttempts.increment()
                throw URLError(.timedOut)
            }
        )
        let handle = uploadEndpoint(session: session, retry: .linear(delay: .milliseconds(10), maxAttempts: 1)).uploadTask(.file(file))

        _ = try await handle.start(resumeFrom: Data("resume".utf8))

        #expect(await resumedAttempts.value == 1)
        #expect(await freshAttempts.value == 1)
    }

    /// An attempt that fails before it is sent — an interceptor rejects it — doesn't
    /// use up the resume data: the first attempt sent resumes, as in a download.
    @Test
    func anUploadResumesOnTheFirstAttemptSent() async throws {
        let resumed = Mutex<[Data]>([])
        let session = MockSession(
            { (request) throws(URLError) in created(request) },
            { (data) throws(URLError) in
                resumed.withLock { $0.append(data) }
                return created(URLRequest(url: URL(string: host)!))
            }
        )
        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: .linear(delay: .zero, maxAttempts: 1)),
            interceptors: [RejectingFirst()],
            api: APIRequest(method: .post, host: host, path: "/upload")
        )

        _ = try await endpoint.uploadTask(dummy).start(resumeFrom: Data("resume".utf8))
        #expect(resumed.withLock { $0 } == [Data("resume".utf8)])
    }

    @Test
    func aTransientFailureOfAResumedDownloadRetriesFromScratch() async throws {
        let resumedAttempts = AtomicCounter()
        let freshAttempts = AtomicCounter()
        let session = MockSession(
            { (request) throws(URLError) in
                await freshAttempts.increment()
                return (Data("file".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )
        await session.stubDownload(responses: [])
        let endpoint = Endpoint<URL, Void>(
            session: ResumeFailingSession(base: session, onResume: { await resumedAttempts.increment() }),
            config: RequestConfig(retry: .linear(delay: .milliseconds(10), maxAttempts: 1)),
            api: APIRequest(method: .get, host: host, path: "/file")
        )

        let url = try await endpoint.downloadTask().start(resumeFrom: Data("resume".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(await resumedAttempts.value == 1)
        #expect(await freshAttempts.value == 1)
    }
}

/// Fails every download resumed from resume data with a transient error; everything
/// else goes to `base`.
private final class ResumeFailingSession: SessionProtocol {
    let base: MockSession
    let onResume: @Sendable () async -> Void
    private let resumed = Mutex<Set<Int>>([])

    init(base: MockSession, onResume: @escaping @Sendable () async -> Void) {
        self.base = base
        self.onResume = onResume
    }

    var sessionDelegate: SessionDelegate { base.sessionDelegate }

    func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask {
        let task = base.downloadTask(withResumeData: data)
        resumed.withLock { _ = $0.insert(task.taskIdentifier) }
        return task
    }

    func awaitDownload(for task: URLSessionDownloadTask) async throws(TransportError) -> (URL, URLResponse) {
        if resumed.withLock({ $0.remove(task.taskIdentifier) != nil }) {
            await onResume()
            throw .network(URLError(.networkConnectionLost))
        }
        return try await base.awaitDownload(for: task)
    }

    func downloadTask(with request: URLRequest) -> URLSessionDownloadTask { base.downloadTask(with: request) }
    func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask { base.uploadTask(with: request, from: data) }
    func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask { base.uploadTask(with: request, fromFile: url) }
    func uploadTask(withResumeData data: Data) -> URLSessionUploadTask { base.uploadTask(withResumeData: data) }
    func awaitUpload(for task: URLSessionUploadTask) async throws(TransportError) -> (Data, URLResponse) { try await base.awaitUpload(for: task) }
    func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask { base.webSocketTask(with: request) }
    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URLSession.AsyncBytes, URLResponse) { try await base.bytes(for: request, delegate: delegate) }
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { try await base.data(for: request, delegate: delegate) }
    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { try await base.download(for: request, delegate: delegate) }
    func download(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { try await base.download(resumeFrom: resumeFrom, delegate: delegate) }
    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { try await base.upload(for: request, from: data, delegate: delegate) }
    func upload(for request: URLRequest, fromFile: URL, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { try await base.upload(for: request, fromFile: fromFile, delegate: delegate) }
}

// MARK: - Real URLSession: cancelling the calling task

/// 192.0.2.1 is TEST-NET-1 (RFC 5737): never routed, so the transfer hangs until
/// its timeout. Cancelling the calling task must end it right away.
@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct DelegateDrivenCancellationTests {

    private var request: URLRequest {
        var request = URLRequest(url: URL(string: "http://192.0.2.1/upload")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        return request
    }

    @Test
    func cancellingTheCallingTaskCancelsAnUploadTask() async {
        let client = Client(session: Session(.ephemeral))
        let request = self.request
        let job = Task { () -> Result<(Data, HTTPURLResponse), TransportError> in
            do throws(TransportError) { return .success(try await client.uploadTask(for: request, .data(Data("x".utf8)))) } catch { return .failure(error) }
        }
        try? await Task.sleep(for: .milliseconds(200))

        let clock = ContinuousClock()
        let start = clock.now
        job.cancel()
        let result = await job.value

        #expect(clock.now - start < .seconds(3), "The transfer kept running after the task was cancelled")
        guard case .failure(let error) = result else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(error.urlError?.code == .cancelled)
    }

    @Test
    func cancellingTheCallingTaskCancelsADownloadTask() async {
        let client = Client(session: Session(.ephemeral))
        let request = URLRequest(url: URL(string: "http://192.0.2.1/file")!, timeoutInterval: 30)
        let job = Task { () -> Result<(url: URL, response: HTTPURLResponse), TransportError> in
            do throws(TransportError) { return .success(try await client.downloadTask(for: request)) } catch { return .failure(error) }
        }
        try? await Task.sleep(for: .milliseconds(200))

        let clock = ContinuousClock()
        let start = clock.now
        job.cancel()
        let result = await job.value

        #expect(clock.now - start < .seconds(3), "The transfer kept running after the task was cancelled")
        guard case .failure(let error) = result else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(error.urlError?.code == .cancelled)
    }
}

// MARK: - Unreadable resume data

/// URLSession makes an upload task from resume data it can't read without a progress
/// nor a request, and the task never completes: reading its progress used to crash
/// the app, and the call would have waited forever. On a real session (no network is
/// reached: the call fails before sending anything).
@Suite(.timeLimit(.minutes(1)))
struct UnreadableResumeDataTests {
    private let unreadable = Data("not resume data".utf8)

    private func endpoint() -> Endpoint<ResponseMock, Void> {
        let api = APIConfiguration(host: "https://base-url.com", session: Session(.ephemeral), config: RequestConfig(retry: .none))
        return Endpoint(api, request: api.request(.post, "/upload"))
    }

    @Test
    func aDirectUploadFailsWithTheErrorURLSessionGivesDownloads() async {
        do {
            _ = try await endpoint().upload(dummy, resumeFrom: unreadable)
            Issue.record("Expected the upload to fail")
        } catch {
            #expect(error.urlError?.code == .unsupportedURL, "Got \(error)")
        }
    }

    @Test
    func aHandleUploadFailsWithTheErrorURLSessionGivesDownloads() async {
        do {
            _ = try await endpoint().uploadTask(dummy).start(resumeFrom: unreadable)
            Issue.record("Expected the upload to fail")
        } catch {
            #expect(error.urlError?.code == .unsupportedURL, "Got \(error)")
        }
    }

}


private extension APIError {
    /// The `URLError` of a transport failure.
    var urlError: URLError? {
        if case .transport(let error) = self { error.urlError } else { nil }
    }
}

/// Rejects the first request it sees with a 503, which is retried.
private final class RejectingFirst: Interceptor, Sendable {
    private let seen = Mutex(false)

    func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
        if !seen.withLock({ defer { $0 = true }; return $0 }) { throw .rejected(status: .serviceUnavailable, body: nil) }
        return request
    }
}

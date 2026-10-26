//
//  WebSocketReconnectTests.swift
//  Beam
//
//  Connection establishment and retry behaviour of the WebSocket `Socket`.
//
//  192.0.2.1 is TEST-NET-1 (RFC 5737): never routed, so the handshake times out,
//  which is a reconnectable error. It needs a network route but no internet access.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Session that counts WebSocket connection attempts

/// Wraps a real Beam `Session` and records every WebSocket task it creates, i.e.
/// every connection attempt the socket makes.
///
/// With `unreachableAfterFirst`, every attempt after the first one goes to an
/// unroutable host instead, simulating a server that disappears after a drop.
private final class CountingWebSocketSession: SessionProtocol {
    private let base = Session()
    private let unreachableAfterFirst: Bool
    private let created = Mutex<[URLSessionWebSocketTask]>([])

    init(unreachableAfterFirst: Bool = false) {
        self.unreachableAfterFirst = unreachableAfterFirst
    }

    var attempts: Int { created.withLock { $0.count } }
    var tasks: [URLSessionWebSocketTask] { created.withLock { $0 } }
    var sessionDelegate: SessionDelegate { base.sessionDelegate }

    func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask {
        var request = request
        if unreachableAfterFirst, attempts > 0 {
            request.url = URL(string: "ws://192.0.2.1/")
            request.timeoutInterval = handshakeTimeout.timeInterval
        }
        let task = base.webSocketTask(with: request)
        created.withLock { $0.append(task) }
        return task
    }

    // Unused by these tests.
    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URLSession.AsyncBytes, URLResponse) { throw URLError(.unsupportedURL) }
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { throw URLError(.unsupportedURL) }
    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { throw URLError(.unsupportedURL) }
    func download(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { throw URLError(.unsupportedURL) }
    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { throw URLError(.unsupportedURL) }
    func upload(for: URLRequest, fromFile: URL, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { throw URLError(.unsupportedURL) }
    func downloadTask(with request: URLRequest) -> URLSessionDownloadTask { base.downloadTask(with: request) }
    func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask { base.downloadTask(withResumeData: data) }
    func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask { base.uploadTask(with: request, from: data) }
    func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask { base.uploadTask(with: request, fromFile: url) }
    func uploadTask(withResumeData data: Data) -> URLSessionUploadTask { base.uploadTask(withResumeData: data) }
}

// MARK: - Timing

/// Handshake timeout for attempts against the unroutable host: short, so each
/// timed-out attempt costs little.
private let handshakeTimeout: Duration = .milliseconds(300)

/// Tolerance applied over a computed worst case, for scheduling overhead and slow CI.
private let timingMargin = 3

/// Longest a correct `connect()` can take with `config`: every attempt uses up its
/// handshake timeout and waits its backoff. Exceeding it means it kept retrying.
private func worstCaseConnectDuration(_ config: RequestConfig) -> Duration {
    let policy = config.retry
    let backoff = (0..<policy.maxAttempts).reduce(Duration.zero) { total, retry in
        total + policy.delay(for: retry + 1)
    }
    return config.timeout * (policy.maxAttempts + 1) + backoff
}

/// Whether `elapsed` shows that a backoff of `delay` was skipped rather than waited out.
private func skipped(_ delay: Duration, elapsed: Duration) -> Bool {
    elapsed < delay / 10
}

/// Polls `condition` until it holds or `limit` elapses.
private func waitUntil(upTo limit: Duration, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + limit
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - Deadline

/// Runs `operation`, cancelling it if it takes longer than `limit`. Returns `nil` on
/// timeout, so a regression that retries forever fails fast instead of hanging.
private func withDeadline<T: Sendable>(
    _ limit: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async -> Result<T, any Error>? {
    await withTaskGroup(of: Result<T, any Error>?.self) { group in
        group.addTask {
            do { return .success(try await operation()) } catch { return .failure(error) }
        }
        group.addTask {
            try? await Task.sleep(for: limit)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

// MARK: - Tests

// The time limit turns a regression into a failure instead of a hang: the bugs
// these tests guard against made the socket retry forever.
@Suite(.serialized, .tags(.network), .timeLimit(.minutes(1)))
struct WebSocketReconnectTests {

    private func makeEndpoint(
        host: String = "ws://192.0.2.1",
        path: String = "/",
        retry: RetryPolicy,
        session: CountingWebSocketSession
    ) -> Endpoint<String, Void> {
        Endpoint<String, Void>(
            session: session,
            config: RequestConfig(retry: retry, timeout: handshakeTimeout),
            api: APIRequest(method: .get, host: host, path: path)
        )
    }

    /// Regression: the attempt counter was reset on every (pre-handshake) "connected",
    /// so an unreachable server was retried forever as `reconnecting(1/N)`.
    @Test
    func givesUpAfterMaxAttempts() async throws {
        let session = CountingWebSocketSession()
        let endpoint = makeEndpoint(retry: .linear(delay: .milliseconds(100), maxAttempts: 2), session: session)

        let limit = worstCaseConnectDuration(endpoint.config) * timingMargin
        let outcome = await withDeadline(limit) { try await endpoint.connect() }
        guard case .failure(let error)? = outcome else {
            Issue.record(outcome == nil
                ? "connect() kept retrying past maxAttempts (still running after \(limit))"
                : "connect() must fail when the server is unreachable")
            return
        }

        #expect((error as? APIError<Void>)?.kind == .timedOut)
        #expect(session.attempts == 3) // 1 initial + 2 retries
    }

    @Test
    func cancellingConnectDuringBackoffReturnsPromptly() async throws {
        let session = CountingWebSocketSession()
        let retry = RetryPolicy.linear(delay: .seconds(30), maxAttempts: 3)
        let endpoint = makeEndpoint(retry: retry, session: session)

        let job = Task { try await endpoint.connect() }

        // Once the first handshake has failed, the socket is waiting its backoff.
        try await waitUntil(upTo: handshakeTimeout * timingMargin) { session.tasks.first?.state == .completed }
        try #require(session.tasks.first?.state == .completed, "The first handshake never failed")

        let clock = ContinuousClock()
        let start = clock.now
        job.cancel()
        let outcome = await job.result

        #expect(skipped(retry.delay(for: 1), elapsed: clock.now - start))
        #expect(session.attempts == 1)
        guard case .failure(let error) = outcome else {
            Issue.record("Expected cancellation")
            return
        }
        #expect((error as? APIError<Void>)?.kind == .cancelled)
    }

    /// A refused connection (nothing listens on the discard port) is not transient,
    /// so it must not be retried.
    @Test
    func refusedConnectionIsNotRetried() async throws {
        let session = CountingWebSocketSession()
        let retry = RetryPolicy.linear(delay: .seconds(30), maxAttempts: 3)
        let endpoint = makeEndpoint(host: "ws://127.0.0.1:9", retry: retry, session: session)

        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await Task { try await endpoint.connect() }.result

        guard case .failure = outcome else {
            Issue.record("connect() must fail when the connection is refused")
            return
        }
        #expect(session.attempts == 1)
        #expect(skipped(retry.delay(for: 1), elapsed: clock.now - start))
    }

    // MARK: - Dropped connections (need internet: echo server)

    private func makeEchoEndpoint(retry: RetryPolicy, session: CountingWebSocketSession) -> Endpoint<String, Void> {
        Endpoint<String, Void>(
            session: session,
            config: RequestConfig(retry: retry),
            api: APIRequest(method: .get, host: "wss://ws.postman-echo.com", path: "/raw")
        )
    }

    /// Drops the connection the way a dead network does: abnormal closure, no close handshake.
    private func drop(_ session: CountingWebSocketSession) {
        session.tasks.last?.cancel(with: .abnormalClosure, reason: nil)
    }

    @Test
    func reconnectsAfterADropAndKeepsWorking() async throws {
        let session = CountingWebSocketSession()
        let connection = try await makeEchoEndpoint(retry: .linear(delay: .milliseconds(100), maxAttempts: 3), session: session).connect()
        defer { Task { await connection.disconnect() } }

        var states = connection.state.makeAsyncIterator()
        drop(session)

        // The lifecycle is on `state` only: reconnecting, then connected again.
        var reconnecting: [String] = []
        while let state = await states.next() {
            if case .reconnecting(let attempt, let max) = state { reconnecting.append("\(attempt)/\(max)") }
            if state == .connected, !reconnecting.isEmpty { break }
        }
        #expect(reconnecting == ["1/3"])
        #expect(session.attempts == 2)

        // The new connection is usable, and its messages keep coming in the same stream.
        try await connection.send(text: "after reconnect")
        var messages = connection.messages.makeAsyncIterator()
        #expect(try await messages.next() == "after reconnect")
    }

    /// Regression for the reported bug: after a drop, a server that stays down was
    /// retried forever as `reconnecting(1/N)`. It must count up and give up.
    @Test
    func givesUpReconnectingWhenTheServerStaysDown() async throws {
        let session = CountingWebSocketSession(unreachableAfterFirst: true)
        let retry = RetryPolicy.linear(delay: .milliseconds(100), maxAttempts: 2)
        let connection = try await makeEchoEndpoint(retry: retry, session: session).connect()

        var states = connection.state.makeAsyncIterator()
        drop(session)

        var reconnecting: [String] = []
        var finalState: WebSocketConnectionState?
        while let state = await states.next() {
            if case .reconnecting(let attempt, let max) = state { reconnecting.append("\(attempt)/\(max)") }
            if case .disconnected = state { finalState = state; break }
            // Any attempt past maxAttempts is already the bug; stop instead of looping forever.
            if reconnecting.count > retry.maxAttempts { break }
        }

        var ending: APIError<Void>?
        do {
            for try await _ in connection.messages {}
        } catch {
            ending = error
        }

        #expect(reconnecting == ["1/2", "2/2"])
        #expect(finalState == .disconnected(reason: .error(.timedOut)))
        #expect(ending?.kind == .timedOut)
        #expect(session.attempts == 3) // first connection + 2 reconnection attempts
    }

    @Test
    func disconnectDuringReconnectBackoffEndsImmediately() async throws {
        let session = CountingWebSocketSession(unreachableAfterFirst: true)
        let retry = RetryPolicy.linear(delay: .seconds(30), maxAttempts: 3)
        let connection = try await makeEchoEndpoint(retry: retry, session: session).connect()

        drop(session)

        var states = connection.state.makeAsyncIterator()
        while let state = await states.next() {
            if case .reconnecting = state { break }
        }

        let clock = ContinuousClock()
        let start = clock.now
        await connection.disconnect()

        var finalState: WebSocketConnectionState?
        while let state = await states.next() {
            finalState = state
            if case .disconnected = state { break }
        }
        #expect(skipped(retry.delay(for: 1), elapsed: clock.now - start))
        #expect(finalState == .disconnected(reason: .intentional))
    }

    @Test
    func consumerStoppingClosesTheSocket() async throws {
        let session = CountingWebSocketSession()
        let connection = try await makeEchoEndpoint(retry: .none, session: session).connect()
        let socket = try #require(session.tasks.first)

        let consumer = Task { for try await _ in connection.messages {} }
        try await Task.sleep(for: .milliseconds(200))
        consumer.cancel()

        let deadline = ContinuousClock.now + .seconds(3)
        while socket.state == .running, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(socket.state != .running)
    }

    // MARK: - Failures before connecting

    /// Building the request fails before any socket is created (here, auth): the
    /// error surfaces as-is and is not retried.
    @Test
    func authFailureIsNotRetried() async throws {
        let session = CountingWebSocketSession()
        let endpoint = Endpoint<String, Void>(
            session: session,
            auth: SignedAuth { (_: inout URLRequest) async throws(AuthError) in throw .missingToken },
            config: RequestConfig(retry: .linear(delay: .seconds(30), maxAttempts: 3)),
            api: APIRequest(method: .get, host: "ws://192.0.2.1", path: "/")
        )

        let outcome = await Task { try await endpoint.connect() }.result
        guard case .failure(let error) = outcome else {
            Issue.record("connect() must fail when authentication fails")
            return
        }
        #expect((error as? APIError<Void>)?.kind == .missingToken)
        #expect(session.attempts == 0)
    }
}

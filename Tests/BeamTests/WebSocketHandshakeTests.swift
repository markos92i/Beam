//
//  WebSocketHandshakeTests.swift
//  Beam
//
//  The WebSocket handshake runs through the same pipeline as an HTTP call:
//  interceptors, auth (with the 401 refresh), validation, retries and monitors.
//
//  192.0.2.1 is TEST-NET-1 (RFC 5737): never routed, so the handshake times out.
//  The other tests need internet access.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Fixtures

/// Records the handshake requests it sees and their context.
private final class HandshakeRecorder: Interceptor {
    let operations = Mutex<[EndpointContext.Operation]>([])
    let statuses = Mutex<[Int]>([])

    var count: Int { operations.withLock { $0.count } }

    func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
        operations.withLock { $0.append(context.operation) }
        var request = request
        request.setValue("handshake", forHTTPHeaderField: "X-Intercepted")
        return request
    }

    func intercept(response: Response, context: EndpointContext) async throws(InterceptorError) -> Response {
        statuses.withLock { $0.append(response.http.statusCode) }
        return response
    }
}

/// Records the failures monitors are told about.
private final class FailureRecorder: Monitor {
    let failures = Mutex<[(kind: APIErrorKind, operation: EndpointContext.Operation)]>([])

    func didFail(_ failure: EndpointFailure, context: EndpointContext) {
        failures.withLock { $0.append((failure.error.kind, context.operation)) }
    }
}

/// Counts credential invalidations.
private final class CountingAuth: AuthProtocol {
    let invalidations = Mutex(0)

    func authenticate(request: inout URLRequest) async throws(AuthError) {
        request.setValue("Bearer expired", forHTTPHeaderField: "Authorization")
    }

    func invalidate() async {
        invalidations.withLock { $0 += 1 }
    }
}

private struct EchoMessage: Codable, Sendable {
    let id: Int
}

private struct RejectingPolicy: TransportTrustPolicy {
    func evaluate(challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.cancelAuthenticationChallenge, nil)
    }
}

// MARK: - Tests

@Suite(.serialized, .tags(.network), .timeLimit(.minutes(1)))
struct WebSocketHandshakeTests {

    @Test
    func interceptorsAndMonitorsSeeEveryHandshakeAttempt() async {
        let recorder = HandshakeRecorder()
        let monitor = FailureRecorder()
        let endpoint = Endpoint<String, Void>(
            monitors: [monitor],
            config: RequestConfig(retry: .linear(delay: .milliseconds(50), maxAttempts: 1), timeout: .milliseconds(300)),
            interceptors: [recorder],
            api: APIRequest(method: .get, host: "ws://192.0.2.1", path: "/")
        )

        do {
            _ = try await endpoint.connect()
            Issue.record("connect() must fail when the server is unreachable")
        } catch {
            #expect(error == .timedOut)
        }

        #expect(recorder.operations.withLock { $0 } == [.connection, .connection])
        let failures = monitor.failures.withLock { $0 }
        #expect(failures.count == 1)
        #expect(failures.first?.kind == .timedOut)
        #expect(failures.first?.operation == .connection)
    }

    @Test
    func responseInterceptorsSeeTheUpgrade() async throws {
        let recorder = HandshakeRecorder()
        let endpoint = Endpoint<String, Void>(
            config: RequestConfig(retry: .none),
            interceptors: [recorder],
            api: APIRequest(method: .get, host: "wss://ws.postman-echo.com", path: "/raw")
        )

        let connection = try await endpoint.connect()
        await connection.disconnect()

        // Response interceptors see the upgrade, and validation accepts it.
        #expect(recorder.statuses.withLock { $0 } == [101])
    }

    @Test
    func aRefusedUpgradeIsAnHTTPError() async {
        let endpoint = Endpoint<String, Void>(
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: "wss://postman-echo.com", path: "/status/403")
        )

        do {
            _ = try await endpoint.connect()
            Issue.record("connect() must fail when the server refuses the upgrade")
        } catch {
            #expect(error == .http(status: .forbidden), "Got \(error)")
        }
    }

    @Test
    func a401OnTheHandshakeRefreshesTheCredentialsOnce() async {
        let auth = CountingAuth()
        let recorder = HandshakeRecorder()
        let endpoint = Endpoint<String, Void>(
            auth: auth,
            config: RequestConfig(retry: .none),
            interceptors: [recorder],
            api: APIRequest(method: .get, host: "wss://postman-echo.com", path: "/status/401")
        )

        do {
            _ = try await endpoint.connect()
            Issue.record("connect() must fail while the server keeps answering 401")
        } catch {
            #expect(error == .http(status: .unauthorized), "Got \(error)")
        }
        #expect(auth.invalidations.withLock { $0 } == 1)
        #expect(recorder.count == 2) // the first try + the repeat after refreshing
    }

    @Test
    func aPinningRejectionOnTheHandshakeIsAnSSLError() async {
        let endpoint = Endpoint<String, Void>(
            session: Session(.ephemeral, trustPolicy: RejectingPolicy()),
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: "wss://ws.postman-echo.com", path: "/raw")
        )

        do {
            _ = try await endpoint.connect()
            Issue.record("connect() must fail when the trust policy rejects the server")
        } catch {
            #expect(error == .sslError, "Got \(error)")
        }
    }

    /// A message that doesn't decode is skipped and logged; the connection goes on and
    /// monitors don't see it, as with a byte stream's elements.
    @Test
    func anUndecodableMessageIsSkippedAndNotReported() async throws {
        let monitor = FailureRecorder()
        let recorder = HandshakeRecorder()
        let endpoint = Endpoint<EchoMessage, Void>(
            monitors: [monitor],
            config: RequestConfig(retry: .linear(delay: .milliseconds(50), maxAttempts: 3)),
            interceptors: [recorder],
            api: APIRequest(method: .get, host: "wss://ws.postman-echo.com", path: "/raw")
        )
        let connection = try await endpoint.connect()
        defer { Task { await connection.disconnect() } }
        try await connection.send(text: "not json")
        try await connection.send(text: #"{"id":1}"#)
        var messages = connection.messages.makeAsyncIterator()
        #expect(try await messages.next() != nil)
        #expect(recorder.count == 1)
        #expect(monitor.failures.withLock { $0.isEmpty })
    }
}

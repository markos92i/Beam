//
//  PipelineTests.swift
//  Beam
//
//  The attempt loop: interceptors, auth (and its 401 refresh), retry policy,
//  validation and monitors.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Fixtures

private struct ErrorBody: Codable, Equatable, Sendable {
    let code: String
}

private let api = APIRequest(method: .get, host: "https://base-url.com", path: "/items/7", pathTemplate: "/items/{id}")

/// Answers each attempt with the next status in `statuses` (the last one repeats).
private func session(_ statuses: [Int], body: Data = json(ResponseMock(id: "1", value: 1)), counter: AtomicCounter = AtomicCounter()) -> MockSession {
    MockSession({ (request) throws(URLError) in
        let attempt = await counter.increment()
        let status = statuses[min(attempt, statuses.count) - 1]
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    })
}

/// Records every monitor event, in order.
private final class Recorder: Monitor {
    private let events = Mutex<[String]>([])
    private let failures = Mutex<[EndpointFailure]>([])
    private let contexts = Mutex<[EndpointContext]>([])
    private let sent = Mutex<[URLRequest]>([])

    var log: [String] { events.withLock { $0 } }
    var lastFailure: EndpointFailure? { failures.withLock { $0.last } }
    var lastContext: EndpointContext? { contexts.withLock { $0.last } }
    var sentRequests: [URLRequest] { sent.withLock { $0 } }

    func didSend(_ request: URLRequest, context: EndpointContext) {
        events.withLock { $0.append("send(\(context.attempt))") }
        sent.withLock { $0.append(request) }
    }
    func didReceive(_ response: Response, context: EndpointContext) {
        events.withLock { $0.append("receive(\(response.http.statusCode))") }
    }
    func willRetry(after error: APIError<Void>, delay: Duration, context: EndpointContext) {
        events.withLock { $0.append("retry(\(error.name))") }
    }
    func didSucceed(_ response: Response, context: EndpointContext) {
        events.withLock { $0.append("succeed") }
        contexts.withLock { $0.append(context) }
    }
    func didFail(_ failure: EndpointFailure, context: EndpointContext) {
        events.withLock { $0.append("fail(\(failure.error.name))") }
        failures.withLock { $0.append(failure) }
        contexts.withLock { $0.append(context) }
    }
}

/// Collects the statuses an interceptor sees.
private final class StatusSpy: Interceptor {
    private let statuses = Mutex<[Int]>([])
    var seen: [Int] { statuses.withLock { $0 } }

    func intercept(response: Response, context: EndpointContext) async throws(InterceptorError) -> Response {
        statuses.withLock { $0.append(response.http.statusCode) }
        return response
    }
}

// MARK: - Auth and 401

struct PipelineAuthTests {

    @Test
    func a401RefreshesAndRepeatsOnceEvenWithoutRetries() async throws {
        let counter = AtomicCounter()
        let invalidated = AtomicFlag()
        let endpoint = Endpoint<ResponseMock, Void>(
            session: session([401, 200], counter: counter),
            auth: MockAuth(onInvalidate: { await invalidated.set() }),
            config: .init(retry: .none),
            api: api
        )

        _ = try await endpoint.data()
        #expect(await counter.value == 2)
        #expect(await invalidated.value)
    }

    @Test
    func a401IsRefreshedOnlyOnce() async {
        let counter = AtomicCounter()
        let endpoint = Endpoint<ResponseMock, Void>(
            session: session([401], counter: counter),
            auth: MockAuth(onInvalidate: {}),
            config: .init(retry: .standard),
            api: api
        )

        do {
            _ = try await endpoint.data()
            Issue.record("Should have thrown")
        } catch {
            #expect(error == .http(status: .unauthorized))
        }
        #expect(await counter.value == 2) // original + one refresh; the policy doesn't retry a 401
    }

    @Test
    func a401WithoutAuthIsNotRetried() async {
        let counter = AtomicCounter()
        let endpoint = Endpoint<ResponseMock, Void>(session: session([401], counter: counter), config: .init(retry: .standard), api: api)

        _ = try? await endpoint.data()
        #expect(await counter.value == 1)
    }

    @Test
    func authSignsAfterTheInterceptors() async throws {
        struct Stamp: Interceptor {
            func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
                var request = request
                request.setValue("stamped", forHTTPHeaderField: "X-Stamp")
                return request
            }
        }
        final class Box: Sendable { let value = Mutex<String?>(nil) }
        let box = Box()
        let auth = SignedAuth { (request: inout URLRequest) async throws(AuthError) in
            box.value.withLock { $0 = request.value(forHTTPHeaderField: "X-Stamp") }
        }
        let endpoint = Endpoint<ResponseMock, Void>(session: session([200]), auth: auth, interceptors: [Stamp()], api: api)

        _ = try await endpoint.data()
        #expect(box.value.withLock { $0 } == "stamped")
    }
}

// MARK: - Interceptors

struct PipelineInterceptorTests {

    @Test
    func interceptorsSeeErrorResponses() async {
        let spy = StatusSpy()
        let endpoint = Endpoint<ResponseMock, Void>(session: session([500]), config: .init(retry: .none), interceptors: [spy], api: api)

        _ = try? await endpoint.data()
        #expect(spy.seen == [500])
    }

    @Test
    func aRejectedSuccessBecomesAnHTTPErrorWithItsBody() async {
        struct EnvelopeCheck: Interceptor {
            func intercept(response: Response, context: EndpointContext) async throws(InterceptorError) -> Response {
                guard case .data(let data) = response.body, let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else {
                    return response
                }
                throw .rejected(status: .unprocessableEntity, body: json(body))
            }
        }
        let endpoint = Endpoint<ResponseMock, ErrorBody>(
            session: session([200], body: json(ErrorBody(code: "E1"))),
            interceptors: [EnvelopeCheck()],
            api: api
        )

        do {
            _ = try await endpoint.data()
            Issue.record("Should have thrown")
        } catch {
            #expect(error == .http(status: .unprocessableEntity))
            #expect(error.body == ErrorBody(code: "E1"))
        }
    }

    @Test
    func aCustomInterceptorErrorReachesTheCallerUnwrapped() async {
        struct DeviceNotRegistered: Error {}
        struct Guard: Interceptor {
            func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
                throw .custom(DeviceNotRegistered())
            }
        }
        let counter = AtomicCounter()
        let endpoint = Endpoint<ResponseMock, Void>(session: session([200], counter: counter), interceptors: [Guard()], api: api)

        do {
            _ = try await endpoint.data()
            Issue.record("Should have thrown")
        } catch {
            guard case .intercepted(let underlying) = error else {
                Issue.record("Unexpected \(error)")
                return
            }
            #expect(underlying is DeviceNotRegistered)
            #expect(error == .intercepted)
        }
        #expect(await counter.value == 0) // nothing was sent
    }
}

// MARK: - Monitors

struct PipelineMonitorTests {

    @Test
    func monitorsSeeEveryStepInOrder() async throws {
        let recorder = Recorder()
        let endpoint = Endpoint<ResponseMock, Void>(
            session: session([503, 200]),
            monitors: [recorder],
            config: .init(retry: .standard),
            api: api
        )

        _ = try await endpoint.data()
        #expect(recorder.log == ["send(0)", "receive(503)", "retry(http(503))", "send(1)", "receive(200)", "succeed"])

        let context = try #require(recorder.lastContext)
        #expect(context.attempt == 1)
        #expect(context.attempts.map(\.status) == [503, 200])
        #expect(context.pathTemplate == "/items/{id}")
        #expect(context.operation == .data)
    }

    @Test
    func monitorsGetTheFinalFailureOnce() async throws {
        let recorder = Recorder()
        let endpoint = Endpoint<ResponseMock, Void>(session: session([500]), monitors: [recorder], config: .init(retry: .standard), api: api)

        _ = try? await endpoint.data()
        #expect(recorder.log.filter { $0.hasPrefix("fail") } == ["fail(http(500))"])

        let failure = try #require(recorder.lastFailure)
        #expect(failure.report.domain == "GET /items/{id} — http(500)")
        #expect(failure.report.info["Attempt"] == "1")
        #expect(failure.response?.http.statusCode == 500)
    }

    @Test
    func failuresBeforeSendingHaveNoRequest() async throws {
        let recorder = Recorder()
        var missing = api
        missing.missingValue = "userID"
        let endpoint = Endpoint<ResponseMock, Void>(session: session([200]), monitors: [recorder], api: missing)

        _ = try? await endpoint.data()
        let failure = try #require(recorder.lastFailure)
        #expect(failure.error == .missingValue("userID"))
        #expect(failure.request == nil)
        #expect(recorder.sentRequests.isEmpty)
    }

    @Test
    func monitorsNeverSeeCredentials() async throws {
        let recorder = Recorder()
        let endpoint = Endpoint<ResponseMock, Void>(session: session([200]), auth: MockAuth(onInvalidate: {}), monitors: [recorder], api: api)

        _ = try await endpoint.data()
        let sent = try #require(recorder.sentRequests.first)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: Report bodies

    @Test
    func reportsIncludeBodiesOnlyWhenAsked() async throws {
        let recorder = Recorder()
        var request = APIRequest(method: .post, host: "https://base-url.com", path: "/users", pathTemplate: "/users")
        request.body = .json(["name": "Ana", "dni": "12345678Z"])
        let endpoint = Endpoint<ResponseMock, Void>(
            session: session([400], body: json(ErrorBody(code: "E9"))),
            monitors: [recorder],
            config: .init(retry: .none),
            api: request
        )

        _ = try? await endpoint.data()
        let failure = try #require(recorder.lastFailure)

        #expect(failure.report.info["ResponseBody"] == nil)
        #expect(failure.report.info["RequestBody"] == nil)

        let detailed = failure.report(including: [.responseBody, .requestBody(redacting: ["dni"])])
        #expect(detailed.info["ResponseBody"]?.contains("E9") == true)
        let requestBody = try #require(detailed.info["RequestBody"])
        #expect(requestBody.contains("Ana"))
        #expect(!requestBody.contains("12345678Z"))
    }

    @Test
    func reportBodiesAreTruncatedTo1kB() async throws {
        let recorder = Recorder()
        let large = json(ErrorBody(code: String(repeating: "x", count: 5000)))
        let endpoint = Endpoint<ResponseMock, Void>(session: session([500], body: large), monitors: [recorder], config: .init(retry: .none), api: api)

        _ = try? await endpoint.data()
        let body = try #require(recorder.lastFailure?.report(including: [.responseBody]).info["ResponseBody"])
        #expect(body.utf8.count <= 1024)
    }
}

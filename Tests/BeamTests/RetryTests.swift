//
//  RetryTests.swift
//  Beam
//

import Foundation
import Testing
@testable import Beam

@Suite
struct RetryTests {

    @Test
    func retryOnServerError() async throws {
        let counter = AtomicCounter()
        let mockBody = ResponseMock(id: "retry-ok", value: 42)
        let expectedData = json(mockBody)

        let session = MockSession({ (request) throws(URLError) in
            let attempt = await counter.increment()
            if attempt < 3 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: RetryPolicy(maxAttempts: 2)),
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/retry")
        )
        let result = try await endpoint.data()
        #expect(result.id == "retry-ok")
        #expect(await counter.value == 3)
    }

    @Test
    func noRetryOnTransportError() async throws {
        let counter = AtomicCounter()

        let session = MockSession({ (request) throws(URLError) in
            await counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: RetryPolicy(maxAttempts: 2)),
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/retry")
        )

        do {
            _ = try await endpoint.data()
            #expect(Bool(false))
        } catch {
            #expect(await counter.value == 1)
        }
    }

    @Test
    func retryOnTimeout() async throws {
        let counter = AtomicCounter()
        let mockBody = ResponseMock(id: "timeout-ok", value: 99)
        let expectedData = json(mockBody)

        let session = MockSession({ (request) throws(URLError) in
            let attempt = await counter.increment()
            if attempt == 1 {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: RetryPolicy(maxAttempts: 2)),
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/retry")
        )

        let result = try await endpoint.data()
        #expect(result.id == "timeout-ok")
        #expect(await counter.value == 2)
    }

    @Test
    func retryExhausted() async throws {
        let counter = AtomicCounter()

        let session = MockSession({ (request) throws(URLError) in
            await counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: RetryPolicy(maxAttempts: 2)),
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/retry")
        )

        do {
            _ = try await endpoint.data()
            #expect(Bool(false))
        } catch {
            #expect(error.status?.rawValue == 503)
            #expect(await counter.value == 3)
        }
    }

    /// RFC 9110 §9.2.2: a POST the server may have applied isn't repeated (it could be applied twice).
    @Test(arguments: [HTTPMethod.post, .patch])
    func nonIdempotentCallIsNotRetriedOnServerError(_ method: HTTPMethod) async throws {
        let counter = AtomicCounter()

        let session = MockSession({ (request) throws(URLError) in
            await counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: RetryPolicy(maxAttempts: 2)),
            api: APIRequest(method: method, host: "https://base-url.com", path: "/retry")
        )

        do {
            _ = try await endpoint.data()
            Issue.record("Expected the 500")
        } catch {
            #expect(error.status == .internalServerError)
            #expect(await counter.value == 1)
        }
    }

    @Test
    func nonIdempotentCallIsNotRetriedOnTimeout() async throws {
        let counter = AtomicCounter()

        let session = MockSession({ (_) throws(URLError) in
            await counter.increment()
            throw URLError(.timedOut)
        })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: RetryPolicy(maxAttempts: 2)),
            api: APIRequest(method: .patch, host: "https://base-url.com", path: "/retry")
        )

        do {
            _ = try await endpoint.data()
            Issue.record("Expected the timeout")
        } catch {
            #expect(await counter.value == 1)
        }
    }

    /// Without connection nothing reached the server, so even a POST is safe to repeat.
    @Test
    func nonIdempotentCallIsRetriedWhenItNeverLeftTheDevice() async throws {
        let counter = AtomicCounter()
        let expectedData = json(ResponseMock(id: "sent", value: 1))

        let session = MockSession({ (request) throws(URLError) in
            if await counter.increment() == 1 { throw URLError(.notConnectedToInternet) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: RetryPolicy(maxAttempts: 2)),
            api: APIRequest(method: .post, host: "https://base-url.com", path: "/retry")
        )

        let result = try await endpoint.data()
        #expect(result.id == "sent")
        #expect(await counter.value == 2)
    }

    @Test
    func retryOnUnauthorizedInvalidatesAuth() async throws {
        let counter = AtomicCounter()
        let flag = AtomicFlag()
        let mockBody = ResponseMock(id: "auth-ok", value: 1)
        let expectedData = json(mockBody)

        let session = MockSession({ (request) throws(URLError) in
            let attempt = await counter.increment()
            if attempt == 1 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let auth = MockAuth(onInvalidate: { await flag.set() })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            auth: auth,
            config: RequestConfig(retry: .standard),
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/auth-retry")
        )

        let result = try await endpoint.data()
        #expect(result.id == "auth-ok")
        #expect(await flag.value)
        #expect(await counter.value == 2)
    }

    @Test
    func cancellingDuringBackoffStopsRetrying() async throws {
        let counter = AtomicCounter()

        let session = MockSession({ (request) throws(URLError) in
            await counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        // A long backoff: before the fix, cancellation was swallowed and the retry ran after it.
        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: .linear(delay: .seconds(30), maxAttempts: 3)),
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/retry")
        )

        let job = Task { try await endpoint.data() }
        try await Task.sleep(for: .milliseconds(200))

        let clock = ContinuousClock()
        let start = clock.now
        job.cancel()
        let result = await job.result

        #expect(clock.now - start < .seconds(5))
        #expect(await counter.value == 1)
        switch result {
        case .success:
            Issue.record("Expected cancellation")
        case .failure(let error):
            #expect((error as? APIError<Void>)?.kind == .cancelled)
        }
    }
}

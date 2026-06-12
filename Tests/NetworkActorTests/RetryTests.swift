//
//  RetryTests.swift
//  NetworkActor
//

import Foundation
import Testing
@testable import NetworkActor

@Suite
struct RetryTests {

    @Test
    func retryOnServerError() async throws {
        let counter = AtomicCounter()
        let mockBody = ResponseMock(id: "retry-ok", value: 42)
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let attempt = await counter.increment()
            if attempt < 3 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let result = try await RetryEndpoint(session: session).call()
        #expect(result.id == "retry-ok")
        #expect(await counter.value == 3)
    }

    @Test
    func noRetryOnClientError() async throws {
        let counter = AtomicCounter()

        let session = MockSession({ request in
            await counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        do {
            _ = try await RetryEndpoint(session: session).call()
            #expect(Bool(false))
        } catch {
            #expect(await counter.value == 1)
        }
    }

    @Test
    func retryOnTimeout() async throws {
        let counter = AtomicCounter()
        let mockBody = ResponseMock(id: "timeout-ok", value: 99)
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let attempt = await counter.increment()
            if attempt == 1 {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let result = try await RetryEndpoint(session: session).call()
        #expect(result.id == "timeout-ok")
        #expect(await counter.value == 2)
    }

    @Test
    func retryExhausted() async throws {
        let counter = AtomicCounter()

        let session = MockSession({ request in
            await counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        do {
            _ = try await RetryEndpoint(session: session).call()
            #expect(Bool(false))
        } catch {
            #expect(error.status?.rawValue == 503)
            #expect(await counter.value == 3)
        }
    }

    @Test
    func retryOnUnauthorizedInvalidatesAuth() async throws {
        let counter = AtomicCounter()
        let flag = AtomicFlag()
        let mockBody = ResponseMock(id: "auth-ok", value: 1)
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let attempt = await counter.increment()
            if attempt == 1 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let auth = MockAuth(onInvalidate: { await flag.set() })

        let service = Service<ResponseMock, Void>(
            client: Client(session: session),
            auth: auth,
            config: ServiceConfig(maxRetries: 1),
            api: ServicePayload(method: .get, host: "https://base-url.com", path: "/auth-retry")
        )

        let result = try await service.data()
        #expect(result.id == "auth-ok")
        #expect(await flag.value)
        #expect(await counter.value == 2)
    }
}

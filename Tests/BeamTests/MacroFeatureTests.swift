//
//  MacroFeatureTests.swift
//  Beam
//
//  Tests for macro features: empty path, optional query params, config override, path validation.
//

import Foundation
import Testing
@testable import Beam

// MARK: - Empty Path API (uses @Get without path argument)

@API(
    host: "https://base-url.com",
    base: "/schedules",
    headers: [:]
)
protocol EmptyPathAPI {
    @Get
    func list() async throws(APIError<Void>) -> [ResponseMock]

    @Post
    func create(body: ResponseMock) async throws(APIError<Void>) -> ResponseMock

    @Put
    func update(body: ResponseMock) async throws(APIError<Void>)
}

// MARK: - Optional Query API

@API(
    host: "https://base-url.com",
    base: "",
    headers: [:]
)
protocol OptionalQueryAPI {
    @Delete("/items/{id}")
    func delete(id: Int, query reason: String?) async throws(APIError<Void>)

    @Get("/search")
    func search(query term: String, query page: Int?) async throws(APIError<Void>) -> [ResponseMock]
}

// MARK: - Config Override API

@API(
    host: "https://base-url.com",
    base: "",
    headers: [:]
)
protocol ConfigOverrideAPI {
    @Get("/resilient", timeout: .seconds(120), retry: .resilient)
    func resilientFetch() async throws(APIError<Void>) -> ResponseMock

    @Post("/fast", timeout: .seconds(5), retry: .none)
    func fastPost(body: ResponseMock) async throws(APIError<Void>)
}

// MARK: - Tests

@Suite
struct MacroFeatureTests {

    // MARK: - Empty Path

    @Test
    func emptyPathGetRequest() async throws {
        let mockBody = [ResponseMock(id: "1", value: 10)]
        let expectedData = json(mockBody)

        let session = MockSession({ (request) throws(URLError) in
            // Verify URL has no trailing empty path segment
            #expect(request.url?.absoluteString == "https://base-url.com/schedules")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let api = EmptyPathAPIClient(session: session)
        let result = try await api.list()
        #expect(result.count == 1)
        #expect(result[0].id == "1")
    }

    @Test
    func emptyPathPostRequest() async throws {
        let input = ResponseMock(id: "new", value: 99)
        let expectedData = json(input)

        let session = MockSession({ (request) throws(URLError) in
            #expect(request.url?.absoluteString == "https://base-url.com/schedules")
            #expect(request.httpMethod == "POST")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let api = EmptyPathAPIClient(session: session)
        let result = try await api.create(body: input)
        #expect(result.id == "new")
    }

    // MARK: - Optional Query Params

    @Test
    func optionalQueryParamWhenNil() async throws {
        let session = MockSession({ (request) throws(URLError) in
            let url = request.url!.absoluteString
            // When reason is nil, it should NOT appear in the URL
            #expect(!url.contains("reason"))
            #expect(url.contains("/items/42"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let api = OptionalQueryAPIClient(session: session)
        try await api.delete(id: 42, query: nil)
    }

    @Test
    func optionalQueryParamWhenPresent() async throws {
        let session = MockSession({ (request) throws(URLError) in
            let url = request.url!.absoluteString
            // When reason is provided, it should appear in the URL
            #expect(url.contains("reason=duplicate"))
            #expect(url.contains("/items/42"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let api = OptionalQueryAPIClient(session: session)
        try await api.delete(id: 42, query: "duplicate")
    }

    @Test
    func mixedOptionalAndRequiredQuery() async throws {
        let mockBody = [ResponseMock(id: "found", value: 1)]
        let expectedData = json(mockBody)

        let session = MockSession({ (request) throws(URLError) in
            let url = request.url!.absoluteString
            #expect(url.contains("term=swift"))
            // page is nil, should not be present
            #expect(!url.contains("page"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let api = OptionalQueryAPIClient(session: session)
        let result = try await api.search(query: "swift", query: nil)
        #expect(result.count == 1)
    }

    @Test
    func mixedOptionalAndRequiredQueryBothPresent() async throws {
        let mockBody = [ResponseMock(id: "found", value: 1)]
        let expectedData = json(mockBody)

        let session = MockSession({ (request) throws(URLError) in
            let url = request.url!.absoluteString
            #expect(url.contains("term=swift"))
            #expect(url.contains("page=2"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let api = OptionalQueryAPIClient(session: session)
        let result = try await api.search(query: "swift", query: 2)
        #expect(result.count == 1)
    }

    // MARK: - Invalid URL reports error

    @Test
    func invalidURLThrowsError() async throws {
        let endpoint = Endpoint<ResponseMock, Void>(
            api: APIRequest(method: .get, host: "ht tp://bad", path: "/users")
        )

        do {
            _ = try await endpoint.data()
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error == .invalidURL)
        }
    }

    // MARK: - Per-route retry override

    /// Regression: `retry: .none` used to resolve to `Optional.none` ("keep the
    /// default"), so the route still retried once.
    @Test
    func retryNoneDisablesRetries() async throws {
        let counter = AtomicCounter()

        let session = MockSession({ (request) throws(URLError) in
            await counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let api = ConfigOverrideAPIClient(session: session)
        do {
            try await api.fastPost(body: ResponseMock(id: "x", value: 1))
            Issue.record("Should have thrown")
        } catch {
            #expect(error.status?.rawValue == 500)
        }
        #expect(await counter.value == 1)
    }

    // MARK: - Session injection

    /// Regression: the generated `init(session:)` copied the configuration field by
    /// field and dropped `logLevel`.
    @Test
    func injectingASessionKeepsTheRestOfTheConfiguration() {
        let original = APIConfiguration(
            host: "https://base-url.com",
            base: "/v1",
            headers: ["X-App": "1"],
            config: RequestConfig(retry: .none, timeout: .seconds(5)),
            interceptors: [RequestIDInterceptor()],
            logLevel: .error
        )
        let injected = original.replacing(session: MockSession({ (_) throws(URLError) in throw URLError(.unknown) }))

        #expect(injected.session is MockSession)
        #expect(injected.host == original.host)
        #expect(injected.base == original.base)
        #expect(injected.headers == original.headers)
        #expect(injected.config.retry == original.config.retry)
        #expect(injected.config.timeout == original.config.timeout)
        #expect(injected.interceptors.count == 1)
        #expect(injected.logLevel == .error)
        #expect(original.replacing(session: nil).session is Session<Foreground>)
    }

    @Test
    func timeoutOverrideIsAppliedToRequest() async throws {
        let session = MockSession({ (request) throws(URLError) in
            #expect(request.timeoutInterval == 5)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let api = ConfigOverrideAPIClient(session: session)
        try await api.fastPost(body: ResponseMock(id: "x", value: 1))
    }
}


// MARK: - Path Template Tests

@API(
    host: "https://api.example.com",
    base: "",
    headers: [:]
)
protocol PathTemplateTestAPI {
    // Using placeholder syntax
    @Get("/users/{id}")
    func getUser(id: Int) async throws(APIError<Void>) -> ResponseMock

    // Multiple placeholders
    @Get("/users/{userId}/posts/{postId}")
    func getUserPost(userId: Int, postId: Int) async throws(APIError<Void>) -> ResponseMock
}

extension MacroFeatureTests {

    @Test
    func pathTemplatePlaceholdersArePreserved() async throws {
        let session = MockSession { (request) throws(URLError) in
            // Verify the actual URL has the interpolated value
            #expect(request.url?.absoluteString == "https://api.example.com/users/42")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (try! JSONEncoder().encode(ResponseMock(id: "1", value: 1)), response)
        }

        let api = PathTemplateTestAPIClient(session: session)
        _ = try await api.getUser(id: 42)
    }

    @Test
    func multiplePathPlaceholders() async throws {
        let session = MockSession { (request) throws(URLError) in
            // Verify the actual URL has the interpolated values
            #expect(request.url?.absoluteString == "https://api.example.com/users/123/posts/456")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (try! JSONEncoder().encode(ResponseMock(id: "1", value: 1)), response)
        }

        let api = PathTemplateTestAPIClient(session: session)
        _ = try await api.getUserPost(userId: 123, postId: 456)
    }
}

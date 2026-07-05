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
    @Get("/resilient", timeout: 120, retry: .resilient)
    func resilientFetch() async throws(APIError<Void>) -> ResponseMock

    @Post("/fast", timeout: 5, retry: .none)
    func fastPost(body: ResponseMock) async throws(APIError<Void>)
}

// MARK: - Tests

@Suite
struct MacroFeatureTests {

    // MARK: - Empty Path

    @Test
    func emptyPathGetRequest() async throws {
        let mockBody = [ResponseMock(id: "1", value: 10)]
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
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
        let expectedData = try JSONEncoder().encode(input)

        let session = MockSession({ request in
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
        let session = MockSession({ request in
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
        let session = MockSession({ request in
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
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
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
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
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
}

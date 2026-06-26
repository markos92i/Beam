//
//  MockIntegrationTests.swift
//  Beam
//
//  Integration tests for inline mock closures on generated API clients.
//

import Testing
import Beam

@API(
    host: "https://mock-test.com",
    base: "/v1",
    headers: [:]
)
protocol MockableAPI {
    @Get("/items/{id}")
    func fetch(id: Int) async throws(APIError<Void>) -> ResponseMock

    @Post("/items")
    func create(body request: UploadRequestMock) async throws(APIError<Void>) -> ResponseMock

    @Delete("/items/{id}")
    func remove(id: Int) async throws(APIError<Void>)
}

// MARK: - Tests

@Suite("Mock Integration")
struct MockIntegrationTests {

    @Test("Mock returns configured success value")
    func mockReturnsSuccess() async throws {
        let expected = ResponseMock(id: "abc", value: 42)

        var api = MockableAPIClient()
        api.onFetch = { _ in expected }

        let result = try await api.fetch(id: 1)
        #expect(result == expected)
    }

    @Test("Mock receives correct parameters")
    func mockReceivesParams() async throws {
        var receivedId: Int?

        var api = MockableAPIClient()
        api.onFetch = { id in
            receivedId = id
            return ResponseMock(id: "test", value: id)
        }

        let result = try await api.fetch(id: 99)
        #expect(receivedId == 99)
        #expect(result.value == 99)
    }

    @Test("Mock throws typed error")
    func mockThrowsError() async {
        var api = MockableAPIClient()
        api.onFetch = { (_) async throws(APIError<Void>) in
            throw APIError.noConnection
        }

        do {
            _ = try await api.fetch(id: 1)
            Issue.record("Expected error to be thrown")
        } catch let error {
            #expect(error == .noConnection)
        }
    }

    @Test("Mock with body parameter")
    func mockWithBody() async throws {
        var receivedContent: String?

        var api = MockableAPIClient()
        api.onCreate = { request in
            receivedContent = request.content
            return ResponseMock(id: "new", value: 1)
        }

        let result = try await api.create(body: UploadRequestMock(content: "hello"))
        #expect(receivedContent == "hello")
        #expect(result.id == "new")
    }

    @Test("Mock Void-returning method")
    func mockVoidReturn() async throws {
        var called = false

        var api = MockableAPIClient()
        api.onRemove = { _ in called = true }

        try await api.remove(id: 5)
        #expect(called)
    }

    @Test("Mock Void-returning method can throw")
    func mockVoidThrows() async {
        var api = MockableAPIClient()
        api.onRemove = { (_) async throws(APIError<Void>) in
            throw APIError.http(status: .forbidden)
        }

        do {
            try await api.remove(id: 1)
            Issue.record("Expected error to be thrown")
        } catch let error {
            #expect(error == .http(status: .forbidden))
        }
    }
}

//
//  MacroIntegrationTests.swift
//  Beam
//
//  Tests that validate the @API macro generates working clients end-to-end.
//

import Foundation
import Testing
@testable import Beam

// MARK: - Macro-generated API

struct OnlineResponse: Codable, Sendable, Equatable {
    let id: Int
    let title: String
    let userId: Int
    let completed: Bool
}

@API(
    host: "https://jsonplaceholder.typicode.com",
    base: "",
    headers: [:]
)
protocol JSONPlaceholderAPI {
    @Get("/todos/{id}")
    func todo(id: Int) async throws(APIError<Void>) -> OnlineResponse

    @Get("/todos")
    func todos(params: [URLQueryItem]) async throws(APIError<Void>) -> [OnlineResponse]

    @Post("/todos")
    func create(body: OnlineResponse) async throws(APIError<Void>) -> OnlineResponse
}

// MARK: - Tests

@Suite(.tags(.network))
struct MacroIntegrationTests {

    let api = JSONPlaceholderAPIClient()

    @Test
    func getWithPathParam() async throws {
        let result = try await api.todo(id: 1)
        #expect(result.id == 1)
        #expect(!result.title.isEmpty)
    }

    @Test
    func getWithQueryParam() async throws {
        let results = try await api.todos(params: [.init(name: "_limit", value: "3")])
        #expect(results.count == 3)
    }

    @Test
    func postWithBody() async throws {
        let newTodo = OnlineResponse(id: 0, title: "Test", userId: 1, completed: false)
        let result = try await api.create(body: newTodo)
        #expect(result.title == "Test")
    }
}

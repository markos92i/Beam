//
//  DataTests.swift
//  NetworkActor
//

import Foundation
import Testing
@testable import Beam

@Suite
struct DataTests {

    @Test
    func requestSuccess() async throws {
        let mockBody = ResponseMock(id: "123", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let api = TestAPIClient(client: Client(session: session))
        let result = try await api.request()
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }

    @Test
    func requestFailure() async throws {
        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let api = TestAPIClient(client: Client(session: session))

        do {
            _ = try await api.request()
            #expect(Bool(false))
        } catch {
            #expect(true)
        }
    }

    @Test
    func requestOnline() async throws {
        let result = try await OnlineAPIClient().fetch()
        #expect(result.id == 1)
    }
}

// MARK: - Online test API (must be at file scope for macro expansion)

struct TodoResponse: Codable, Sendable {
    let id: Int
    let title: String
}

@API(
    host: "https://jsonplaceholder.typicode.com",
    base: "",
    headers: [:],
    client: Client()
)
protocol OnlineAPI {
    @Get("/todos/1")
    func fetch() async throws(APIError<Void>) -> TodoResponse
}

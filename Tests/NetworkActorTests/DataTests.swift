//
//  DataTests.swift
//  NetworkActor
//

import Foundation
import Testing
@testable import NetworkActor

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

        let result = try await RequestEndpoint(session: session).call()
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }

    @Test
    func requestFailure() async throws {
        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        do {
            _ = try await RequestEndpoint(session: session).call()
            #expect(Bool(false))
        } catch {
            #expect(true)
        }
    }

    @Test
    func requestOnline() async throws {
        struct OnlineEndpoint: Endpoint {
            var task: DataTask<OnlineResponse, Void> {
                Get("https://jsonplaceholder.typicode.com", "/todos/1")
            }
        }
        struct OnlineResponse: Codable, Sendable {
            let id: Int
            let title: String
        }

        let result = try await OnlineEndpoint().call()
        #expect(result.id == 1)
    }
}

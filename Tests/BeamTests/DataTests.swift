//
//  DataTests.swift
//  Beam
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

        let api = TestAPIClient(session: session)
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

        let api = TestAPIClient(session: session)

        await #expect(throws: APIError<Void>.self) {
            _ = try await api.request()
        }
    }
}

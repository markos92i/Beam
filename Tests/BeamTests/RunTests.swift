//
//  RunTests.swift
//  NetworkActor
//

import Foundation
import Testing
@testable import Beam

@Suite
struct RunTests {

    @Test
    func runEmitsSuccess() async {
        let mockBody = ResponseMock(id: "run-1", value: 42)
        let expectedData = try! JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let service: Service<ResponseMock, Void> = _buildRoute(
            config: _APIConfiguration(
                host: "https://base-url.com",
                base: "",
                components: [Use(Client(session: session))]
            ),
            method: .get,
            path: "/ok"
        )

        var receivedSuccess: ResponseMock?
        for await event in service.run({ try await $0.data() }) {
            if case .success(let value) = event { receivedSuccess = value }
        }

        #expect(receivedSuccess == mockBody)
    }

    @Test
    func runEmitsFailureOnError() async {
        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let service: Service<ResponseMock, Void> = _buildRoute(
            config: _APIConfiguration(
                host: "https://base-url.com",
                base: "",
                components: [Use(Client(session: session))]
            ),
            method: .get,
            path: "/ok"
        )

        var receivedFailure: APIError<Void>?
        for await event in service.run({ try await $0.data() }) {
            if case .failure(let error) = event { receivedFailure = error }
        }

        #expect(receivedFailure != nil)
    }

}

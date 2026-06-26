//
//  DownloadTests.swift
//  Beam
//

import Foundation
import Testing
@testable import Beam

@Suite
struct DownloadTests {

    // MARK: - Direct (async throws)

    @Test
    func downloadSuccess() async throws {
        let expectedData = "Downloaded file content".data(using: .utf8)!

        let session = MockSession({ request in
            let headers = ["Content-Disposition": "attachment; filename=\"download-\(UUID().uuidString).bin\""]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
            return (expectedData, response)
        })

        let api = TestAPIClient(session: session)
        let url = try await api.download()
        let data = try Data(contentsOf: url)
        #expect(data == expectedData)
        try? FileManager.default.removeItem(at: url)
    }

    @Test
    func downloadCancel() async throws {
        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return ("data".data(using: .utf8)!, response)
        }, nil, delay: 2)

        let api = TestAPIClient(session: session)

        do {
            let job = Task { try await api.download() }
            Task {
                try await Task.sleep(for: .seconds(0.5))
                job.cancel()
            }
            _ = try await job.value
            #expect(Bool(false))
        } catch {
            #expect(error is APIError<Void>)
        }
    }
}

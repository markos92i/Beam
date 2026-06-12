//
//  DownloadTests.swift
//  NetworkActor
//

import Foundation
import Testing
@testable import NetworkActor

@Suite
struct DownloadTests {

    @Test
    func downloadSuccess() async throws {
        let expectedData = "Downloaded file content".data(using: .utf8)!

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let url = try await DownloadEndpoint(session: session).call()
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

        let endpoint = DownloadEndpoint(session: session)

        do {
            Task {
                try await Task.sleep(for: .seconds(0))
                await endpoint.cancel()
            }
            let url = try await endpoint.call()
            #expect(Bool(false))
            try? FileManager.default.removeItem(at: url)
        } catch {
            #expect(error == .cancelled)
        }
    }

    @Test
    func downloadResumeSuccess() async throws {
        let expectedData = "Downloaded file content".data(using: .utf8)!
        let resumeData = "{ resume: true }".data(using: .utf8)!

        let session = MockSession(nil, { data in
            let response = HTTPURLResponse(url: URL(string: "https://base-url.com")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            #expect(data == resumeData)
            return (expectedData, response)
        })

        let url = try await DownloadEndpoint(session: session).call(resumeFrom: resumeData)
        let data = try Data(contentsOf: url)
        #expect(data == expectedData)
        try? FileManager.default.removeItem(at: url)
    }
}

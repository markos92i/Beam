//
//  UploadTests.swift
//  NetworkActor
//

import Foundation
import Testing
@testable import Beam

@Suite
struct UploadTests {

    @Test
    func uploadSuccess() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let api = TestAPIClient(client: Client(session: session))
        let result = try await api.upload(body: UploadRequestMock(content: "Dummy"))
        #expect(result.id == mockBody.id)
    }

    @Test
    func uploadCancel() async throws {
        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }, nil, delay: 2)

        let api = TestAPIClient(client: Client(session: session))

        do {
            let job = Task { try await api.upload(body: UploadRequestMock(content: "Dummy")) }
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

    @Test
    func uploadURLSuccess() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try expectedData.write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            let data = try Data(contentsOf: temporaryURL)
            return (data, response)
        })

        let api = TestAPIClient(client: Client(session: session))
        let result = try await api.uploadURL(url: temporaryURL)
        #expect(result.id == mockBody.id)
    }

    @Test
    func uploadResumeSuccess() async throws {
        let expectedResponse = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(expectedResponse)
        let resumeData = "{ resume: true }".data(using: .utf8)!

        let session = MockSession(nil, { data in
            let response = HTTPURLResponse(url: URL(string: "https://base-url.com")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            #expect(data == resumeData)
            return (expectedData, response)
        })

        let api = TestAPIClient(client: Client(session: session))
        let result = try await api.uploadResume(resumeFrom: resumeData)
        #expect(result.id == expectedResponse.id)
    }
}

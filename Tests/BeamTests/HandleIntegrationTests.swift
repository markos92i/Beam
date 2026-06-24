//
//  HandleIntegrationTests.swift
//  Beam
//
//  Integration tests for DownloadTask and UploadTask using the
//  task-based path (downloadTask/uploadTask + delegate).
//
//  ⚠️ Requires internet. Run manually:
//  swift test --filter "Handle Integration"
//

import Foundation
import Testing
@testable import Beam

// MARK: - Test API

@API(
    host: "https://postman-echo.com",
    base: "",
    headers: [:]
)
protocol HandleTestAPI {
    @Get("/get", task: .download)
    func downloadFile() async throws(APIError<Void>) -> URL

    @Post("/post", task: .upload)
    func upload(body: HandleUploadBody) async throws(APIError<Void>) -> HandleUploadResponse
}

struct HandleUploadBody: Codable, Sendable {
    let content: String
}

struct HandleUploadResponse: Codable, Sendable {
    let json: HandleUploadBody?
}

// MARK: - Tests

@Suite("Handle Integration", .tags(.network))
struct HandleIntegrationTests {

    @Test("DownloadTask downloads file via task-based path")
    func downloadSuccess() async throws {
        let handle = HandleTestAPIClient().downloadFileTask()
        #expect(!handle.id.isEmpty)
        let url = try await handle.start()
        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("UploadTask uploads and decodes response via task-based path")
    func uploadSuccess() async throws {
        let handle = HandleTestAPIClient().uploadTask(body: HandleUploadBody(content: "test-beam"))
        #expect(!handle.id.isEmpty)
        let response = try await handle.start()
        #expect(response.json?.content == "test-beam")
    }
}

//
//  TaskIntegrationTests.swift
//  Beam
//
//  Integration tests for DownloadTask and UploadTask using the
//  task-based path (foreground, inline result via task delegate).
//
//  ⚠️ Requires internet. Run manually:
//  swift test --filter "Task Integration"
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
protocol TaskTestAPI {
    @Get("/get", task: .download)
    func downloadFile() async throws(APIError<Void>) -> URL

    @Post("/post", task: .upload)
    func upload(body: TaskUploadBody) async throws(APIError<Void>) -> TaskUploadResponse
}

struct TaskUploadBody: Codable, Sendable {
    let content: String
}

struct TaskUploadResponse: Codable, Sendable {
    let json: TaskUploadBody?
}

// MARK: - Tests

@Suite("Task Integration", .tags(.network))
struct TaskIntegrationTests {

    @Test("DownloadTask downloads file via task-based path")
    func downloadSuccess() async throws {
        let task = TaskTestAPIClient().downloadFileTask()
        #expect(!task.id.isEmpty)
        let url = try await task.start()
        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("UploadTask uploads and decodes response via task-based path")
    func uploadSuccess() async throws {
        let task = TaskTestAPIClient().uploadTask(body: TaskUploadBody(content: "test-beam"))
        #expect(!task.id.isEmpty)
        let response = try await task.start()
        #expect(response.json?.content == "test-beam")
    }
}

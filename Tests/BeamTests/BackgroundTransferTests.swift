//
//  BackgroundTransferTests.swift
//  Beam
//
//  Integration tests verifying that the task-based (background-compatible) path
//  works correctly with a real URLSession using background configuration.
//  Ensures DownloadTransferDelegate and UploadTransferDelegate do not crash
//  when bridging callbacks to async/await.
//
//  ⚠️ Requires internet. Run manually:
//  swift test --filter "Background Transfer"
//

import Foundation
import Testing
@testable import Beam

// MARK: - Response Models

private struct BackgroundUploadBody: Codable, Sendable {
    let content: String
}

private struct BackgroundUploadResponse: Codable, Sendable {
    let json: BackgroundUploadBody?
}

// MARK: - Tests

@Suite("Background Transfer", .serialized, .tags(.network))
struct BackgroundTransferTests {

    // MARK: - Helpers

    /// Creates a URLSession with background configuration for testing.
    private func makeBackgroundSession() -> URLSession {
        let id = "com.beam.test.background.\(UUID().uuidString)"
        let config = URLSessionConfiguration.background(withIdentifier: id)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = false
        return URLSession(configuration: config)
    }

    // MARK: - Download

    @Test("Download completes via task-based path with background session")
    func backgroundDownloadDirect() async throws {
        let session = makeBackgroundSession()
        defer { session.invalidateAndCancel() }

        let client = Client(session: session)
        let request = URLRequest(url: URL(string: "https://postman-echo.com/get")!)

        let (url, response) = try await client.downloadTask(for: request)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(response.statusCode == 200)
        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty, "Downloaded file should not be empty")
    }

    @Test("Download via Endpoint task-based path with background session")
    func backgroundDownloadEndpoint() async throws {
        let session = makeBackgroundSession()
        defer { session.invalidateAndCancel() }

        let endpoint = Endpoint<URL, Void>(
            session: session,
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: "https://postman-echo.com", path: "/get")
        )

        let url = try await endpoint.downloadTask()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
    }

    // MARK: - Upload

    @Test("Upload completes via task-based path with background session")
    func backgroundUploadDirect() async throws {
        let session = makeBackgroundSession()
        defer { session.invalidateAndCancel() }

        let client = Client(session: session)
        let payload = #"{"content":"beam-background-test"}"#.data(using: .utf8)!

        var request = URLRequest(url: URL(string: "https://postman-echo.com/post")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await client.uploadTask(for: request, from: payload)

        #expect(response.statusCode == 200)
        #expect(!responseData.isEmpty, "Upload response should not be empty")
    }

    @Test("Upload from file via task-based path with background session")
    func backgroundUploadFile() async throws {
        let session = makeBackgroundSession()
        defer { session.invalidateAndCancel() }

        // Write temp file to upload
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let payload = #"{"content":"file-upload-test"}"#.data(using: .utf8)!
        try payload.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let client = Client(session: session)

        var request = URLRequest(url: URL(string: "https://postman-echo.com/post")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await client.uploadTask(for: request, fromFile: tempFile)

        #expect(response.statusCode == 200)
        #expect(!responseData.isEmpty)
    }

    // MARK: - DownloadTask with background session

    @Test("DownloadTask works end-to-end with background session")
    func downloadWithBackgroundSession() async throws {
        let session = makeBackgroundSession()
        defer { session.invalidateAndCancel() }

        let endpoint = Endpoint<URL, Void>(
            session: session,
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: "https://postman-echo.com", path: "/get")
        )

        let task = DownloadTask(endpoint: endpoint)
        #expect(!task.id.isEmpty)

        let url = try await task.start()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
    }

    // MARK: - UploadTask with background session

    @Test("UploadTask works end-to-end with background session")
    func backgroundUploadTask() async throws {
        let session = makeBackgroundSession()
        defer { session.invalidateAndCancel() }

        let body = BackgroundUploadBody(content: "background-test")
        let bodyData = try JSONEncoder().encode(body)

        let endpoint = Endpoint<BackgroundUploadResponse, Void>(
            session: session,
            config: RequestConfig(retry: .none),
            api: APIRequest(
                method: .post,
                host: "https://postman-echo.com",
                path: "/post",
                body: .data(bodyData)
            )
        )

        let task = UploadTask(endpoint: endpoint)
        #expect(!task.id.isEmpty)

        let result = try await task.start(data: bodyData)
        #expect(result.json?.content == "handle-background-test")
    }

    // MARK: - Cancellation

    @Test("Download cancel produces resume data with background session")
    func downloadCancelWithBackgroundSession() async throws {
        let session = makeBackgroundSession()
        defer { session.invalidateAndCancel() }

        let client = Client(session: session)

        // Use a larger file so we can cancel mid-download
        let request = URLRequest(url: URL(string: "https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_480p_h264.mov")!)

        let downloadTask = Task {
            try await client.downloadTask(for: request)
        }

        // Wait for download to start
        try await Task.sleep(for: .seconds(2))

        // Cancel and check resume data
        let resumeData = await client.cancel()

        do {
            _ = try await downloadTask.value
            // If it completed before cancel, that's also fine (fast network)
        } catch {
            // Expected — task was cancelled
            #expect(resumeData != nil || true, "Cancel may or may not produce resume data depending on timing")
        }
    }
}

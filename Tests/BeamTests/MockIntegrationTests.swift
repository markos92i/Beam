//
//  MockIntegrationTests.swift
//  Beam
//
//  Integration tests for inline mock closures on generated API clients.
//

import Foundation
import Testing
import Beam

@API(
    host: "https://mock-test.com",
    base: "/v1",
    headers: [:]
)
protocol MockableAPI {
    @Get("/items/{id}")
    func fetch(id: Int) async throws(APIError<Void>) -> ResponseMock

    @Post("/items")
    func create(body request: UploadRequestMock) async throws(APIError<Void>) -> ResponseMock

    @Delete("/items/{id}")
    func remove(id: Int) async throws(APIError<Void>)

    @Post("/items/{id}/file", task: .upload)
    func upload(id: Int, body: HTTPBody) async throws(APIError<Void>) -> ResponseMock

    @Get("/items/{id}/file", task: .download)
    func download(id: Int) async throws(APIError<Void>) -> URL

    // Overloaded names get one mock each: `onItemId` and `onItemCode`.
    @Get("/items/{id}")
    func item(id: Int) async throws(APIError<Void>) -> ResponseMock

    @Get("/items/by-code/{code}")
    func item(code: String) async throws(APIError<Void>) -> ResponseMock
}

// MARK: - Tests

@Suite("Mock Integration")
struct MockIntegrationTests {

    @Test("Mock returns configured success value")
    func mockReturnsSuccess() async throws {
        let expected = ResponseMock(id: "abc", value: 42)

        var api = MockableAPIClient()
        api.onFetch = { _ in expected }

        let result = try await api.fetch(id: 1)
        #expect(result == expected)
    }

    @Test("Mock receives correct parameters")
    func mockReceivesParams() async throws {
        var receivedId: Int?

        var api = MockableAPIClient()
        api.onFetch = { id in
            receivedId = id
            return ResponseMock(id: "test", value: id)
        }

        let result = try await api.fetch(id: 99)
        #expect(receivedId == 99)
        #expect(result.value == 99)
    }

    @Test("Mock throws typed error")
    func mockThrowsError() async {
        var api = MockableAPIClient()
        api.onFetch = { (_) async throws(APIError<Void>) in
            throw .transport(.network(URLError(.notConnectedToInternet)))
        }

        do {
            _ = try await api.fetch(id: 1)
            Issue.record("Expected error to be thrown")
        } catch let error {
            #expect(error == .noConnection)
        }
    }

    @Test("Mock with body parameter")
    func mockWithBody() async throws {
        var receivedContent: String?

        var api = MockableAPIClient()
        api.onCreate = { request in
            receivedContent = request.content
            return ResponseMock(id: "new", value: 1)
        }

        let result = try await api.create(body: UploadRequestMock(content: "hello"))
        #expect(receivedContent == "hello")
        #expect(result.id == "new")
    }

    @Test("Mock Void-returning method")
    func mockVoidReturn() async throws {
        var called = false

        var api = MockableAPIClient()
        api.onRemove = { _ in called = true }

        try await api.remove(id: 5)
        #expect(called)
    }

    @Test("Mock Void-returning method can throw")
    func mockVoidThrows() async {
        var api = MockableAPIClient()
        api.onRemove = { (_) async throws(APIError<Void>) in
            throw APIError.http(status: .forbidden)
        }

        do {
            try await api.remove(id: 1)
            Issue.record("Expected error to be thrown")
        } catch let error {
            #expect(error == .http(status: .forbidden))
        }
    }

    // The client's real session is never reached: a request would fail against
    // `mock-test.com`, so a passing test means the mock answered.

    @Test("Mock answers a direct upload, also with onProgress")
    func mockUpload() async throws {
        var api = MockableAPIClient()
        api.onUpload = { id, _ in ResponseMock(id: "uploaded", value: id) }

        let result = try await api.upload(id: 7, body: .data(Data("x".utf8), contentType: .data))
        #expect(result == ResponseMock(id: "uploaded", value: 7))

        let withProgress = try await api.upload(id: 8, body: .data(Data("x".utf8), contentType: .data), onProgress: { _ in })
        #expect(withProgress.value == 8)
    }

    @Test("Mock answers a direct download")
    func mockDownload() async throws {
        let file = URL.temporaryDirectory.appending(component: "mock-download")
        var api = MockableAPIClient()
        api.onDownload = { _ in file }

        #expect(try await api.download(id: 1) == file)
    }

    @Test("Overloaded routes have a mock each")
    func mockOverloads() async throws {
        var api = MockableAPIClient()
        api.onItemId = { id in ResponseMock(id: "id", value: id) }
        api.onItemCode = { code in ResponseMock(id: code, value: 0) }

        #expect(try await api.item(id: 3).id == "id")
        #expect(try await api.item(code: "abc").id == "abc")
    }
}

// MARK: - Handles

/// Transfer routes on an API with a background session: every handle kind exists.
/// Mocked handles never reach the network nor the background session.
@API(
    host: "https://mock-test.com",
    base: "/v1",
    background: backgroundTestSession
)
protocol MockableTransfersAPI {
    @Post("/items/{id}/file", task: .upload)
    func upload(id: Int, body: HTTPBody) async throws(APIError<Void>) -> ResponseMock

    @Put("/items/{id}/raw", task: .upload)
    func uploadFile(id: Int, url file: URL) async throws(APIError<Void>) -> ResponseMock

    @Get("/items/{id}/file", task: .download)
    func download(id: Int) async throws(APIError<Void>) -> URL

    @Post("/items/{id}/file", task: .upload)
    func resumeUpload(id: Int, body: HTTPBody, resumeFrom data: Data) async throws(APIError<Void>) -> ResponseMock

    @Get("/items/{id}/file", task: .download)
    func resumeDownload(id: Int, resumeFrom data: Data) async throws(APIError<Void>) -> URL
}

@Suite("Mock Integration — handles")
struct HandleMockTests {
    private static let body = HTTPBody.data(Data("x".utf8), contentType: .data)
    private static let file = URL.temporaryDirectory.appending(component: "mock-file")

    /// How long a mock keeps "transferring" in the cancellation tests: cancelling
    /// must end the call in a small fraction of it.
    private static let mockDuration = Duration.seconds(30)

    @Test("The route's mock answers its upload handles")
    func uploadHandles() async throws {
        var api = MockableTransfersAPIClient()
        api.onUpload = { id, _ in ResponseMock(id: "mock", value: id) }

        #expect(try await api.upload(id: 1, body: Self.body).value == 1)
        #expect(try await api.uploadTask(id: 2, body: Self.body).start().value == 2)
        #expect(try await api.uploadTask(id: 4, body: Self.body).start(resumeFrom: Data()).value == 4)
        #expect(try await api.uploadBackgroundTask(id: 5, body: Self.body).start(id: "doc").value == 5)
    }

    /// The handle takes the file when it is created, as the direct call does.
    @Test("In an upload route with a file, the mock gets the handle's file")
    func uploadFileHandle() async throws {
        var api = MockableTransfersAPIClient()
        api.onUploadFile = { id, file in ResponseMock(id: file.lastPathComponent, value: id) }
        #expect(try await api.uploadFileTask(id: 1, url: Self.file).start().id == "mock-file")
        #expect(try await api.uploadFileBackgroundTask(id: 2, url: Self.file).start(id: "doc").id == "mock-file")
    }

    @Test("The route's mock answers its download handles")
    func downloadHandles() async throws {
        var api = MockableTransfersAPIClient()
        api.onDownload = { _ in Self.file }

        #expect(try await api.downloadTask(id: 1).start() == Self.file)
        #expect(try await api.downloadTask(id: 1).start(resumeFrom: Data()) == Self.file)
        #expect(try await api.downloadBackgroundTask(id: 1).start(id: "doc") == Self.file)
    }

    /// Handles take the resume data in `start(resumeFrom:)`: the mock receives it from there.
    @Test("In a route with resumeFrom, the mock gets the resume data given to start")
    func resumeHandles() async throws {
        let resume = Data("resume".utf8)
        var api = MockableTransfersAPIClient()
        api.onResumeUpload = { id, _, data in ResponseMock(id: String(decoding: data, as: UTF8.self), value: id) }
        api.onResumeDownload = { _, data in URL(fileURLWithPath: "/resume/\(data.count)") }

        #expect(try await api.resumeUpload(id: 1, body: Self.body, resumeFrom: resume).id == "resume")
        #expect(try await api.resumeUploadTask(id: 2, body: Self.body).start(resumeFrom: resume).id == "resume")
        #expect(try await api.resumeDownload(id: 1, resumeFrom: resume).lastPathComponent == "6")
        #expect(try await api.resumeDownloadTask(id: 2).start(resumeFrom: resume).lastPathComponent == "6")
        #expect(try await api.resumeDownloadBackgroundTask(id: 3).start(id: "doc", resumeFrom: resume).lastPathComponent == "6")
        // Started without resume data, the mock gets empty data.
        #expect(try await api.resumeDownloadTask(id: 4).start().lastPathComponent == "0")
    }

    /// Without a mock, the direct call of a route with `resumeFrom` resumes the transfer.
    @Test("A route with resumeFrom resumes the transfer")
    func resumeRoutesResume() async throws {
        let resume = Data("resume".utf8)
        let ok = HTTPURLResponse(url: URL(string: "https://mock-test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let uploads = MockSession(uploadResume: { (data) throws(URLError) in
            (json(ResponseMock(id: String(decoding: data, as: UTF8.self), value: 1)), ok)
        })
        #expect(try await MockableTransfersAPIClient(session: uploads).resumeUpload(id: 1, body: Self.body, resumeFrom: resume).id == "resume")

        let file = URL.temporaryDirectory.appending(component: "resumed-\(UUID().uuidString)")
        try resume.write(to: file)
        let downloads = MockSession(downloadResume: { (data) throws(URLError) in
            guard data == resume else { throw URLError(.cannotDecodeContentData) }
            return (file, ok)
        })
        let stored = try await MockableTransfersAPIClient(session: downloads).resumeDownload(id: 1, resumeFrom: resume)
        defer { try? FileManager.default.removeItem(at: stored.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: stored) == resume)
    }

    @Test("cancel() cancels a mock in progress")
    func cancelStopsTheMock() async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        var api = MockableTransfersAPIClient()
        api.onUpload = { id, _ in
            startedContinuation.yield()
            try? await Task.sleep(for: Self.mockDuration)
            return ResponseMock(id: "late", value: id)
        }
        let handle = api.uploadTask(id: 1, body: Self.body)

        let clock = ContinuousClock()
        let start = clock.now
        let call = Task { () async -> Result<ResponseMock, APIError<Void>> in
            do throws(APIError<Void>) { return .success(try await handle.start()) } catch { return .failure(error) }
        }
        for await _ in started { break }
        await handle.cancel()

        let result = await call.value
        #expect(throws: APIError<Void>.self) { try result.get() }
        if case .failure(let error) = result { #expect(error == .cancelled) }
        #expect(clock.now - start < Self.mockDuration / 10)
    }

    @Test("Cancelling the calling task cancels a mock in progress")
    func taskCancellationStopsTheMock() async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        var api = MockableTransfersAPIClient()
        api.onDownload = { _ in
            startedContinuation.yield()
            try? await Task.sleep(for: Self.mockDuration)
            return Self.file
        }
        let handle = api.downloadTask(id: 1)

        let clock = ContinuousClock()
        let start = clock.now
        let call = Task { () async -> Result<URL, APIError<Void>> in
            do throws(APIError<Void>) { return .success(try await handle.start()) } catch { return .failure(error) }
        }
        for await _ in started { break }
        call.cancel()

        let result = await call.value
        if case .failure(let error) = result { #expect(error == .cancelled) } else { Issue.record("Expected .cancelled") }
        #expect(clock.now - start < Self.mockDuration / 10)
    }
}

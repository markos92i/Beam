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

        let session = MockSession({ (request) throws(URLError) in
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
        let session = MockSession({ (request) throws(URLError) in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return ("data".data(using: .utf8)!, response)
        }, nil, delay: 2)

        let api = TestAPIClient(session: session)

        do {
            let job = Task { try await api.download() }
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                job.cancel()
            }
            _ = try await job.value
            #expect(Bool(false))
        } catch {
            #expect(error is APIError<Void>)
        }
    }

    // MARK: - Files of failed attempts

    private static func file(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "download-test-\(UUID().uuidString)")
        try Data(content.utf8).write(to: url)
        return url
    }

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://mock-test.com/file")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func endpoint(_ session: MockSession, retry: RetryPolicy = .none) -> Endpoint<URL, Void> {
        Endpoint(session: session, config: RequestConfig(retry: retry), api: APIRequest(method: .get, host: "https://mock-test.com", path: "/file"))
    }

    /// A download answered with an error status keeps its body in the error and deletes the file.
    @Test
    func aFailedDownloadLeavesNoFile() async throws {
        let failed = try Self.file("not found")
        let session = MockSession()
        await session.stubDownload(responses: [(failed, Self.response(404))])
        do {
            _ = try await Self.endpoint(session).download()
            Issue.record("Expected the download to fail")
        } catch {
            #expect(error.rawBody == Data("not found".utf8))
        }
        #expect(!FileManager.default.fileExists(atPath: failed.path()))
    }

    /// The file of an attempt that is retried is deleted; the last one is handed out.
    @Test
    func aRetriedAttemptLeavesNoFile() async throws {
        let failed = try Self.file("unavailable")
        let succeeded = try Self.file("content")
        let session = MockSession()
        await session.stubDownload(responses: [(failed, Self.response(503)), (succeeded, Self.response(200))])
        let url = try await Self.endpoint(session, retry: .linear(delay: .zero, maxAttempts: 1)).download()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(!FileManager.default.fileExists(atPath: failed.path()))
        #expect(try Data(contentsOf: url) == Data("content".utf8))
    }

    // MARK: - The response of an HTTP error

    private static let errorPage = HTTPURLResponse(
        url: URL(string: "https://gateway.example.com/final/page")!, statusCode: 502, httpVersion: nil,
        headerFields: ["Content-Type": "text/html; charset=utf-8", "Retry-After": "30"]
    )!

    /// An HTTP error keeps the server's response: its final URL and headers, e.g. to
    /// show an HTML error page in a web view.
    @Test
    func anHTTPErrorKeepsTheResponseOfADataCall() async throws {
        let session = MockSession({ (_) throws(URLError) in (Data("<html>Bad gateway</html>".utf8), Self.errorPage) })
        do {
            _ = try await TestAPIClient(session: session).request()
            Issue.record("Expected the call to fail")
        } catch {
            #expect(error.response?.url == Self.errorPage.url)
            #expect(error.response?.value(forHTTPHeaderField: "Retry-After") == "30")
            #expect(error.asVoid.response?.mimeType == "text/html")
        }
    }

    @Test
    func anHTTPErrorKeepsTheResponseOfADownload() async throws {
        let session = MockSession()
        await session.stubDownload(responses: [(try Self.file("<html>Bad gateway</html>"), Self.errorPage)])
        do {
            _ = try await Self.endpoint(session).download()
            Issue.record("Expected the download to fail")
        } catch {
            #expect(error.response?.url == Self.errorPage.url)
            #expect(error.rawBody == Data("<html>Bad gateway</html>".utf8))
        }
    }

    /// A request an interceptor rejects before sending it has no response.
    @Test
    func aRequestRejectedBeforeSendingHasNoResponse() async throws {
        struct Rejecting: Interceptor {
            func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
                throw .rejected(status: .forbidden, body: nil)
            }
        }
        let endpoint = Endpoint<URL, Void>(
            session: MockSession(), config: RequestConfig(retry: .none), interceptors: [Rejecting()],
            api: APIRequest(method: .get, host: "https://mock-test.com", path: "/file")
        )
        do {
            _ = try await endpoint.download()
            Issue.record("Expected the download to fail")
        } catch {
            #expect(error.status == .forbidden)
            #expect(error.response == nil)
        }
    }

    /// A data call's error body is already in memory: it is kept whole, beyond the
    /// limit that applies to downloads and streams.
    @Test
    func aDataCallKeepsTheWholeErrorBody() async throws {
        let body = Data(repeating: 0x61, count: HTTPErrorBody<Void>.limit + 1024)
        let session = MockSession({ (request) throws(URLError) in (body, Self.response(404)) })
        let api = TestAPIClient(session: session)
        do {
            _ = try await api.request()
            Issue.record("Expected the call to fail")
        } catch {
            #expect(error.rawBody?.count == body.count)
        }
    }
}

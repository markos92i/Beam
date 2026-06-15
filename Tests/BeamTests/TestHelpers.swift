//
//  TestHelpers.swift
//  NetworkActor
//

import Foundation
@testable import Beam

// MARK: - Test API (macro-based)

@API(
    host: "https://base-url.com",
    base: "",
    headers: [:],
    client: Client()
)
protocol TestAPI {
    @Get("/ok")
    func request() async throws(APIError<Void>) -> ResponseMock

    @Get("/upload", task: .upload)
    func upload(body: UploadRequestMock) async throws(APIError<Void>) -> ResponseMock

    @Get("/upload", task: .upload)
    func uploadURL(url: URL) async throws(APIError<Void>) -> ResponseMock

    @Get("/upload", task: .upload)
    func uploadResume(resumeFrom data: Data) async throws(APIError<Void>) -> ResponseMock

    @Get("/download", task: .download)
    func download() async throws(APIError<Void>) -> URL

    @Get("/download", task: .download)
    func downloadResume(resumeFrom data: Data) async throws(APIError<Void>) -> URL

    @Get("/retry")
    func retry() async throws(APIError<Void>) -> ResponseMock
}

// MARK: - Helpers

actor AtomicCounter {
    var value = 0
    @discardableResult
    func increment() -> Int { value += 1; return value }
}

actor AtomicFlag {
    var value = false
    func set() { value = true }
}

// MARK: - Mock Auth

actor MockAuth: AuthProtocol {
    typealias Token = MockToken

    let onInvalidate: @Sendable () async -> Void

    init(onInvalidate: @escaping @Sendable () async -> Void) {
        self.onInvalidate = onInvalidate
    }

    var authHeader: [String : String] { ["Authorization": "Bearer mock"] }
    var token: MockToken { MockToken() }

    func set(token: MockToken) async {}
    func invalidate() async { await onInvalidate() }
    func clear() async {}
}

struct MockToken: AuthToken {
    var isValid: Bool { true }
}

// MARK: - Response Models

struct ResponseMock: Codable, Equatable, Sendable {
    let id: String
    let value: Int
}

struct UploadRequestMock: Codable, Sendable {
    let content: String
}

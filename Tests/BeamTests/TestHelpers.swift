//
//  TestHelpers.swift
//  Beam
//

import Foundation
import Testing
@testable import Beam

// MARK: - Tags

extension Tag {
    @Tag static var network: Self
}

// MARK: - Test API (macro-based)

@API(
    host: "https://base-url.com",
    base: "",
    headers: [:]
)
protocol TestAPI {
    @Get("/ok")
    func request() async throws(APIError<Void>) -> ResponseMock

    @Get("/upload", task: .upload)
    func upload(body: UploadRequestMock) async throws(APIError<Void>) -> ResponseMock

    @Get("/upload", task: .upload)
    func uploadURL(url: URL) async throws(APIError<Void>) -> ResponseMock

    @Get("/download", task: .download)
    func download() async throws(APIError<Void>) -> URL

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
    let onInvalidate: @Sendable () async -> Void

    init(onInvalidate: @escaping @Sendable () async -> Void) {
        self.onInvalidate = onInvalidate
    }

    // MARK: - AuthProtocol

    func authenticate(request: inout URLRequest) async throws {
        request.addValue("Bearer mock", forHTTPHeaderField: "Authorization")
    }

    func invalidate() async { await onInvalidate() }
}

// MARK: - Auth Test Token

struct TestToken: AuthToken, Sendable {
    let id: String
    let isValid: Bool

    static let valid = TestToken(id: "valid-token", isValid: true)
    static let expired = TestToken(id: "expired-token", isValid: false)
}

// MARK: - Response Models

struct ResponseMock: Codable, Equatable, Sendable {
    let id: String
    let value: Int
}

struct UploadRequestMock: Codable, Sendable {
    let content: String
}

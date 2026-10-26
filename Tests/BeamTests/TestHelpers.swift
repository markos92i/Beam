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

    @Post("/upload", task: .upload)
    func upload(body: UploadRequestMock) async throws(APIError<Void>) -> ResponseMock

    @Post("/upload", task: .upload)
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

    func authenticate(request: inout URLRequest) async {
        request.addValue("Bearer mock", forHTTPHeaderField: "Authorization")
    }

    func invalidate() async { await onInvalidate() }
}

// MARK: - Response Models

struct ResponseMock: Codable, Equatable, Sendable {
    let id: String
    let value: Int
}

struct UploadRequestMock: Codable, Sendable {
    let content: String
}

// MARK: - Encoding

/// Encodes a test fixture. Mock session handlers throw only `URLError`, like a real
/// session, so fixtures are encoded without throwing.
func json(_ value: some Encodable) -> Data {
    try! JSONEncoder().encode(value)
}

// MARK: - Endpoint by hand

/// An API with the given services around one hand-built request, which keeps its own host.
func testAPI(
    for request: APIRequest,
    session: any SessionProtocol = Session(),
    auth: (any AuthProtocol)? = nil,
    monitors: [any Monitor] = [],
    config: RequestConfig = .standard,
    interceptors: [any Interceptor] = [],
    logLevel: LogLevel? = nil
) -> APIConfiguration {
    APIConfiguration(host: request.host, session: session, auth: auth, monitors: monitors, config: config, interceptors: interceptors, logLevel: logLevel)
}

// Endpoints around one hand-built request, with the API's services given one by one:
// shorthand for the tests that exercise the call pipeline rather than how an API is
// declared. Bodies are read by type, through the public initializers.

extension Endpoint where Success: Decodable & SendableMetatype, Failure: Decodable & SendableMetatype {
    init(session: any SessionProtocol = Session(), auth: (any AuthProtocol)? = nil, monitors: [any Monitor] = [], config: RequestConfig = .standard, interceptors: [any Interceptor] = [], logLevel: LogLevel? = nil, api request: APIRequest) {
        self.init(testAPI(for: request, session: session, auth: auth, monitors: monitors, config: config, interceptors: interceptors, logLevel: logLevel), request: request)
    }
}

extension Endpoint where Success: Decodable & SendableMetatype, Failure == Void {
    init(session: any SessionProtocol = Session(), auth: (any AuthProtocol)? = nil, monitors: [any Monitor] = [], config: RequestConfig = .standard, interceptors: [any Interceptor] = [], logLevel: LogLevel? = nil, api request: APIRequest) {
        self.init(testAPI(for: request, session: session, auth: auth, monitors: monitors, config: config, interceptors: interceptors, logLevel: logLevel), request: request)
    }
}

extension Endpoint where Success == Void, Failure: Decodable & SendableMetatype {
    init(session: any SessionProtocol = Session(), auth: (any AuthProtocol)? = nil, monitors: [any Monitor] = [], config: RequestConfig = .standard, interceptors: [any Interceptor] = [], logLevel: LogLevel? = nil, api request: APIRequest) {
        self.init(testAPI(for: request, session: session, auth: auth, monitors: monitors, config: config, interceptors: interceptors, logLevel: logLevel), request: request)
    }
}

extension Endpoint where Success == Void, Failure == Void {
    init(session: any SessionProtocol = Session(), auth: (any AuthProtocol)? = nil, monitors: [any Monitor] = [], config: RequestConfig = .standard, interceptors: [any Interceptor] = [], logLevel: LogLevel? = nil, api request: APIRequest) {
        self.init(testAPI(for: request, session: session, auth: auth, monitors: monitors, config: config, interceptors: interceptors, logLevel: logLevel), request: request)
    }
}

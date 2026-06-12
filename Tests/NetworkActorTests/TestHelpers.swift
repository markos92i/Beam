//
//  TestHelpers.swift
//  NetworkActor
//

import Foundation
@testable import NetworkActor

// MARK: - Endpoints

struct RequestEndpoint: Endpoint {
    let session: any NetworkSession

    var task: DataTask<ResponseMock, Void> {
        Get("https://base-url.com", "/ok")
        Use(Client(session: session))
    }
}

struct UploadEndpoint: Endpoint {
    let session: any NetworkSession

    var task: UploadTask<ResponseMock, Void> {
        Get("https://base-url.com", "/upload")
        Body(.data("Dummy file content".data(using: .utf8)!))
        Use(Client(session: session))
    }
}

struct DownloadEndpoint: Endpoint {
    let session: any NetworkSession

    var task: DownloadTask<Void> {
        Get("https://base-url.com", "/download")
        Use(Client(session: session))
    }
}

struct RetryEndpoint: Endpoint {
    let session: any NetworkSession

    var task: DataTask<ResponseMock, Void> {
        Get("https://base-url.com", "/retry")
        Use(Client(session: session))
        Config(ServiceConfig(maxRetries: 2))
    }
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

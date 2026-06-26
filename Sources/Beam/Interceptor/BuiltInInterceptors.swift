//
//  BuiltInInterceptors.swift
//  Beam
//
//  Built-in interceptors for common use cases.
//

import Foundation

// MARK: - RequestID

/// Adds a unique request ID header to every request.
/// Useful for correlating requests with server-side logs.
public struct RequestIDInterceptor: RequestInterceptor {
    private let headerName: String

    public init(headerName: String = "X-Request-ID") {
        self.headerName = headerName
    }

    public func intercept(request: URLRequest) async -> URLRequest {
        var request = request
        request.setValue(UUID().uuidString, forHTTPHeaderField: headerName)
        return request
    }
}

// MARK: - DynamicHeaders

/// Adds headers resolved at request time via a closure.
/// Useful for values that change between requests (device state, feature flags, etc).
public struct DynamicHeadersInterceptor: RequestInterceptor {
    private let provider: @Sendable () async -> [String: String]

    public init(_ provider: @escaping @Sendable () async -> [String: String]) {
        self.provider = provider
    }

    public func intercept(request: URLRequest) async -> URLRequest {
        var request = request
        let headers = await provider()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

// MARK: - Logging

/// Logs request/response info via provided closures.
/// Useful for analytics, debugging, or external observability systems.
public struct LoggingInterceptor: RequestInterceptor {
    private let onRequest: (@Sendable (URLRequest) async -> Void)?
    private let onResponse: (@Sendable (Response) async -> Void)?

    public init(
        onRequest: (@Sendable (URLRequest) async -> Void)? = nil,
        onResponse: (@Sendable (Response) async -> Void)? = nil
    ) {
        self.onRequest = onRequest
        self.onResponse = onResponse
    }

    public func intercept(request: URLRequest) async -> URLRequest {
        await onRequest?(request)
        return request
    }

    public func intercept(response: Response) async -> Response {
        await onResponse?(response)
        return response
    }
}

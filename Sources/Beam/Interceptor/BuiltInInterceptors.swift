//
//  BuiltInInterceptors.swift
//  Beam
//
//  Built-in interceptors for common use cases.
//

import Foundation

// MARK: - RequestID

/// Adds a unique request ID header to every request.
public struct RequestIDInterceptor: Interceptor {
    private let headerName: String

    public init(headerName: String = "X-Request-ID") {
        self.headerName = headerName
    }

    public func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
        var request = request
        request.setValue(UUID().uuidString, forHTTPHeaderField: headerName)
        return request
    }
}

// MARK: - DynamicHeaders

/// Adds headers resolved by a closure at request time.
public struct DynamicHeadersInterceptor: Interceptor {
    private let provider: @Sendable () async -> [String: String]

    public init(_ provider: @escaping @Sendable () async -> [String: String]) {
        self.provider = provider
    }

    public func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
        var request = request
        let headers = await provider()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

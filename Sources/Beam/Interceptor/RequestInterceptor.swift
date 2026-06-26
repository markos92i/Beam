//
//  RequestInterceptor.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

/// Represents the body of a response, either in-memory data or a file on disk.
public enum ResponseBody: Sendable {
    /// In-memory response body (from data/upload operations).
    case data(Data)
    /// File URL on disk (from download operations).
    case file(URL)
}

/// The full response context passed to interceptors.
public struct Response: Sendable {
    public let http: HTTPURLResponse
    public let body: ResponseBody

    public init(http: HTTPURLResponse, body: ResponseBody) {
        self.http = http
        self.body = body
    }
}

/// A protocol for intercepting requests before they are sent and responses after they arrive.
///
/// Use cases:
/// - Adding dynamic headers (device ID, session correlation, A/B test flags)
/// - Logging request/response metrics to external systems
/// - Modifying requests based on runtime conditions
/// - Inspecting or transforming responses (e.g. logging status, saving downloads)
///
/// Interceptors are configured at the `_APIConfiguration` level and applied
/// to all requests made through that API client.
///
/// Both methods have default no-op implementations, so conforming types
/// only need to implement the phase(s) they care about.
public protocol RequestInterceptor: Sendable {
    /// Called before the request is executed. Return the (possibly modified) request.
    func intercept(request: URLRequest) async -> URLRequest

    /// Called after a successful response is received (data, upload, or download).
    /// Return the (possibly modified) response.
    func intercept(response: Response) async -> Response
}

// MARK: - Default Implementations

extension RequestInterceptor {
    public func intercept(request: URLRequest) async -> URLRequest { request }
    public func intercept(response: Response) async -> Response { response }
}

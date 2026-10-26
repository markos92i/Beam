//
//  Interceptor.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

// MARK: - Response

/// The body of a response, as interceptors and monitors see it.
public enum ResponseBody: Sendable {
    /// Data and upload operations, and any error response.
    case data(Data)
    /// Download operations.
    case file(URL)
    /// A successful byte stream or WebSocket upgrade: its content goes to the caller only.
    case stream
}

/// A response as interceptors and monitors see it.
public struct Response: Sendable {
    public let http: HTTPURLResponse
    public let body: ResponseBody

    public init(http: HTTPURLResponse, body: ResponseBody) {
        self.http = http
        self.body = body
    }

    /// `.undefined` for codes Beam doesn't know.
    public var status: HTTPStatus { http.httpStatus }

    /// The `Content-Type` the server sent, or the one Foundation infers.
    public var contentType: ContentType? { http.contentType }

    var errorBody: Data? {
        switch body {
        case .data(let data): data
        case .file(let url): FileUtils.errorBody(at: url)
        case .stream: nil
        }
    }
}

// MARK: - Interceptor

/// Modifies or rejects every request and response, on every attempt, before auth and status validation.
public protocol Interceptor: Sendable {
    /// Called before each attempt is sent.
    func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest

    /// Called with each response, whatever its status.
    func intercept(response: Response, context: EndpointContext) async throws(InterceptorError) -> Response
}

extension Interceptor {
    public func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest { request }
    public func intercept(response: Response, context: EndpointContext) async throws(InterceptorError) -> Response { response }
}

// MARK: - InterceptorError

/// Failures an interceptor can raise.
public enum InterceptorError: Error {
    /// Surfaces as ``APIError/auth(_:)``.
    case auth(AuthError)
    /// `body` is decoded into the route's `Failure`: surfaces as ``APIError/http(status:body:response:)``.
    case rejected(status: HTTPStatus, body: Data?)
    /// Surfaces, unwrapped, as ``APIError/intercepted(_:)``.
    case custom(any Error)
}

// MARK: - EndpointContext

/// What interceptors and monitors know about the call in progress.
public struct EndpointContext: Sendable {
    /// The kind of operation being performed.
    public enum Operation: Sendable, Equatable {
        case data, upload, download, stream, connection
    }

    /// A finished attempt.
    public struct Attempt: Sendable, Equatable {
        /// The HTTP status received, or `nil` when no response arrived.
        public let status: Int?
        /// From building the request to receiving, or failing to receive, the response.
        public let duration: Duration
    }

    /// The call's id, as in the logs.
    public let id: String
    public let method: HTTPMethod
    /// The route without its values, e.g. `/v1/users/{id}`.
    public let pathTemplate: String
    public let operation: Operation
    /// `0` for the first attempt.
    public let attempt: Int
    /// Finished attempts, in order.
    public let attempts: [Attempt]
    /// Time since the call started.
    public let elapsed: Duration
}

//
//  APIError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation

/// The error thrown by every Beam call. Lower-layer errors are wrapped intact;
/// compare with ``APIErrorKind`` for everyday checks.
public enum APIError<Failure: Sendable>: Error, Identifiable {
    // MARK: Orchestration

    case invalidURL
    /// An ``APIValues`` property used by the route is `nil`.
    case missingValue(String)
    /// An upload's request has a body of its own, which would be dropped.
    case conflictingUploadData
    /// Any cancellation: task, URLSession, auth or socket.
    case cancelled

    // MARK: Server

    /// A non-2xx response. `response` is `nil` only when an interceptor rejected the request before sending.
    case http(status: HTTPStatus, body: HTTPErrorBody<Failure> = .empty, response: HTTPURLResponse? = nil)

    // MARK: Other layers

    /// The exchange failed (`.network`), or a file the transfer needs failed (`.file`).
    case transport(TransportError)
    case connection(WebSocketError)
    case auth(AuthError)
    case coding(CodingError)
    /// A file failure outside the transfer: a multipart file, moving a finished download.
    case storage(FileError)
    /// An interceptor's own error (``InterceptorError/custom(_:)``), unwrapped.
    case intercepted(any Error)
}

// MARK: - Kind

/// The payload-free kind of an ``APIError``: used to compare errors, pick messages and group crash reports.
public enum APIErrorKind: Hashable, Sendable {
    case invalidURL
    case missingValue(String)
    case conflictingUploadData
    case cancelled
    case http(status: HTTPStatus)
    case noConnection
    case timedOut
    case serverUnreachable
    case sslError
    case noResponse
    case connectionClosed
    case sendFailed
    case missingToken
    case invalidCredentials
    case tokenExpired
    case encode
    case decode
    case typeMismatch
    case storage
    case intercepted
    case unknown
}

extension APIError {
    public var kind: APIErrorKind {
        switch self {
        case .invalidURL: .invalidURL
        case .missingValue(let name): .missingValue(name)
        case .conflictingUploadData: .conflictingUploadData
        case .cancelled: .cancelled
        case .http(let status, _, _): .http(status: status)
        case .transport(.network(let error)): Self.kind(of: error)
        case .transport(.file): .storage
        case .connection(let error):
            switch error {
            case .closed, .unexpectedDisconnection, .pingFailed: .connectionClosed
            case .network(let urlError): Self.kind(of: urlError)
            case .sendFailed: .sendFailed
            }
        case .auth(let error):
            switch error {
            case .missingToken: .missingToken
            case .invalidCredentials: .invalidCredentials
            case .failedToRefreshToken: .tokenExpired
            case .cancelled: .cancelled
            }
        case .coding(let error):
            switch error {
            case .encoding: .encode
            case .decoding: .decode
            case .typeMismatch: .typeMismatch
            }
        case .storage: .storage
        case .intercepted: .intercepted
        }
    }

    private static func kind(of error: URLError) -> APIErrorKind {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: .noConnection
        case .timedOut: .timedOut
        case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost: .serverUnreachable
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired: .sslError
        case .badServerResponse: .noResponse
        case .cancelled: .cancelled
        case .fileDoesNotExist, .fileIsDirectory, .noPermissionsToReadFile, .cannotCreateFile,
             .cannotOpenFile, .cannotCloseFile, .cannotWriteToFile, .cannotRemoveFile,
             .cannotMoveFile: .storage
        default: .unknown
        }
    }

    /// Whether the error is of the given kind.
    public static func == (error: APIError, kind: APIErrorKind) -> Bool { error.kind == kind }

    public static func != (error: APIError, kind: APIErrorKind) -> Bool { error.kind != kind }
}

// MARK: - Properties

extension APIError {
    /// Stable numeric code of the kind, used as the crash report code.
    public var id: Int { kind.id }

    /// Stable short name of the kind, for logs and crash report grouping.
    public var name: String { kind.name }

    @inline(always)
    public var status: HTTPStatus? {
        if case .http(let status, _, _) = self { status } else { nil }
    }

    /// The decoded error body of an `.http` error.
    @inline(always)
    public var body: Failure? {
        if case .http(_, let body, _) = self { body.value } else { nil }
    }

    /// The `.http` error body as sent, even if it doesn't decode; up to 64 KB for downloads and streams.
    public var rawBody: Data? {
        if case .http(_, let body, _) = self { body.data } else { nil }
    }

    /// The server's response of an `.http` error.
    public var response: HTTPURLResponse? {
        if case .http(_, _, let response) = self { response } else { nil }
    }

    /// Expected in normal use (cancelled, offline, timed out), so not worth reporting.
    public var isExpected: Bool {
        switch kind {
        case .cancelled, .noConnection, .timedOut: true
        default: false
        }
    }

    var icon: String { kind.info.icon }

    /// A short technical description, for logs.
    public var detail: String {
        if case .connection(.closed(let code, let reason)) = self {
            return "WebSocket closed with code \(code.rawValue)\(reason.map { ": \($0)" } ?? "")"
        }
        return kind.info.detail
    }
}

extension APIErrorKind {
    /// Stable numeric code, used as the crash report code.
    public var id: Int { info.id }

    /// Stable short name, for logs and crash report grouping.
    public var name: String { info.name }

    /// Never change ids or names: crash reports group by them. Id 12 was removed; don't reuse it.
    fileprivate var info: (id: Int, name: String, icon: String, detail: String) {
        switch self {
        case .encode: (0, "encode", "􀃮", "Failed to encode request body")
        case .decode: (1, "decode", "􀃮", "Failed to decode response")
        case .typeMismatch: (3, "typeMismatch", "􀭉", "Body doesn't have the expected form")
        case .invalidURL: (10, "invalidURL", "􀺾", "Could not construct a valid URL from host and path")
        case .conflictingUploadData: (11, "conflictingUploadData", "􀈂", "The upload's request has a body of its own, which would be dropped")
        case .missingToken: (13, "missingToken", "􂅦", "No authentication token available")
        case .tokenExpired: (14, "tokenExpired", "􂅦", "Authentication token has expired")
        case .missingValue(let name): (15, "missingValue(\(name))", "􀅍", "APIValues.\(name) is not available")
        case .invalidCredentials: (16, "invalidCredentials", "􂅦", "Credentials rejected by the server")
        case .noConnection: (20, "noConnection", "􀤆", "No internet connection")
        case .timedOut: (21, "timedOut", "􀐫", "Request timed out")
        case .serverUnreachable: (22, "serverUnreachable", "􀙥", "Server is unreachable")
        case .sslError: (23, "sslError", "􀞡", "SSL certificate validation failed")
        case .noResponse: (24, "noResponse", "􀙥", "Server did not return an HTTP response")
        case .connectionClosed: (25, "connectionClosed", "􂇥", "WebSocket connection closed")
        case .sendFailed: (26, "sendFailed", "􂇥", "WebSocket message could not be sent")
        case .http(let status): (status.rawValue, "http(\(status.rawValue))", "􀘯", status.name)
        case .intercepted: (30, "intercepted", "􀌈", "An interceptor rejected the call")
        case .storage: (90, "storage", "􁘥", "Storage operation failed")
        case .cancelled: (91, "cancelled", "􀁠", "Request was cancelled")
        case .unknown: (99, "unknown", "􀁜", "Unknown error")
        }
    }
}

// MARK: - Classification

extension APIError {
    /// A 401 isn't retryable here: auth refreshes and repeats it on its own.
    var isRetryable: Bool {
        switch self {
        case .http(let status, _, _): status.type == .serverError
        case .transport(.network(let error)): error.isTransient
        case .connection(let error): error.isRetryable
        default: false
        }
    }

    var logDescription: String {
        switch self {
        case .http(let status, _, _): "HTTP: \(status.rawValue)"
        case .transport(let error): error.logDescription
        case .connection(let error): error.logDescription
        case .auth(let error): error.logDescription
        case .coding(let error): error.logDescription
        case .storage(let error): error.logDescription
        case .intercepted(let error): "Interceptor error: \(error)"
        default: detail
        }
    }
}

// MARK: - Conversion

extension APIError {
    init(_ error: TransportError) {
        if case .network(let urlError) = error, urlError.code == .cancelled { self = .cancelled } else { self = .transport(error) }
    }

    init(_ error: WebSocketError) {
        switch error {
        case .network(let urlError) where urlError.code == .cancelled,
             .sendFailed(let urlError) where urlError.code == .cancelled:
            self = .cancelled
        default:
            self = .connection(error)
        }
    }

    init(_ error: AuthError) {
        self = error == .cancelled ? .cancelled : .auth(error)
    }

    init(_ error: InterceptorError, response: HTTPURLResponse?, decodeBody: (Data?) -> HTTPErrorBody<Failure>) {
        switch error {
        case .auth(let error): self.init(error)
        case .rejected(let status, let body): self = .http(status: status, body: decodeBody(body), response: response)
        case .custom(let error) where error is CancellationError: self = .cancelled
        case .custom(let error): self = .intercepted(error)
        }
    }
}

// MARK: - Type erasure

extension APIError {
    /// Converts to `APIError<Void>`, dropping the decoded HTTP body; the raw one stays.
    public var asVoid: APIError<Void> {
        switch self {
        case .invalidURL: .invalidURL
        case .missingValue(let name): .missingValue(name)
        case .conflictingUploadData: .conflictingUploadData
        case .cancelled: .cancelled
        case .http(let status, let body, let response): .http(status: status, body: body.withoutValue, response: response)
        case .transport(let error): .transport(error)
        case .connection(let error): .connection(error)
        case .auth(let error): .auth(error)
        case .coding(let error): .coding(error)
        case .storage(let error): .storage(error)
        case .intercepted(let error): .intercepted(error)
        }
    }
}

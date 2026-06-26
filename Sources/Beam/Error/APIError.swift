//
//  APIError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation

public enum APIError<Failure: Sendable>: Error, Identifiable {
    // Serialization
    case encode
    case decode
    case unsupportedType
    case typeMismatch

    // Invalid request
    case invalidURL
    case invalidFormat
    case missingUploadData
    case missingToken
    case tokenExpired

    // Network
    case noConnection
    case timedOut
    case serverUnreachable
    case sslError
    case noResponse
    case connectionClosed(code: Int, reason: String?)

    // Server response
    case http(status: HTTPStatus, body: Failure? = nil)

    // System
    case storage
    case cancelled
    case unknown

    // MARK: - Identifiable
    public var id: Int {
        switch self {
        case .encode: 0
        case .decode: 1
        case .unsupportedType: 2
        case .typeMismatch: 3

        case .invalidURL: 10
        case .invalidFormat: 11
        case .missingUploadData: 12
        case .missingToken: 13
        case .tokenExpired: 14

        case .noConnection: 20
        case .timedOut: 21
        case .serverUnreachable: 22
        case .sslError: 23
        case .noResponse: 24
        case .connectionClosed: 25

        case .http(let code, _): code.rawValue

        case .storage: 90
        case .cancelled: 91
        case .unknown: 99
        }
    }
}

// MARK: - Properties
extension APIError {
    public var status: HTTPStatus? {
        if case .http(let status, _) = self { status } else { nil }
    }

    public var body: Failure? {
        if case .http(_, let body) = self { body } else { nil }
    }

    var isSilent: Bool {
        switch self {
        case .cancelled, .noConnection, .timedOut: true
        default: false
        }
    }

    /// Whether this error should trigger WebSocket reconnection.
    var isReconnectable: Bool {
        switch self {
        case .connectionClosed(let code, _):
            code != 1000 && code != 1001
        case .noConnection, .timedOut, .serverUnreachable, .unknown:
            true
        default:
            false
        }
    }

    public var name: String {
        switch self {
        case .http(let status, _): "http(\(status.rawValue))"
        case .encode: "encode"
        case .decode: "decode"
        case .unsupportedType: "unsupportedType"
        case .typeMismatch: "typeMismatch"
        case .invalidURL: "invalidURL"
        case .invalidFormat: "invalidFormat"
        case .missingUploadData: "missingUploadData"
        case .missingToken: "missingToken"
        case .tokenExpired: "tokenExpired"
        case .noConnection: "noConnection"
        case .timedOut: "timedOut"
        case .serverUnreachable: "serverUnreachable"
        case .sslError: "sslError"
        case .noResponse: "noResponse"
        case .connectionClosed: "connectionClosed"
        case .storage: "storage"
        case .cancelled: "cancelled"
        case .unknown: "unknown"
        }
    }

    var icon: String {
        switch self {
        case .encode, .decode: "􀃮"
        case .unsupportedType, .typeMismatch: "􀭉"
        case .http: "􀘯"
        case .missingToken, .tokenExpired: "􂅦"
        case .invalidURL, .invalidFormat: "􀺾"
        case .noResponse, .serverUnreachable: "􀙥"
        case .connectionClosed: "􂇥"
        case .sslError: "􀞡"
        case .timedOut: "􀐫"
        case .noConnection: "􀤆"
        case .cancelled: "􀁠"
        case .storage: "􁘥"
        case .missingUploadData: "􀈂"
        case .unknown: "􀁜"
        }
    }

    public var detail: String {
        switch self {
        case .http(let status, _): status.name
        case .encode: "Failed to encode request body"
        case .decode: "Failed to decode response"
        case .unsupportedType: "Response type is not supported"
        case .typeMismatch: "Response type does not match expected"
        case .invalidURL: "Could not construct a valid URL from host and path"
        case .invalidFormat: "The response format is not valid"
        case .noResponse: "Server did not return an HTTP response"
        case .missingUploadData: "Upload body is empty — no data to send"
        case .missingToken: "No authentication token available"
        case .tokenExpired: "Authentication token has expired"
        case .noConnection: "No internet connection"
        case .timedOut: "Request timed out"
        case .serverUnreachable: "Server is unreachable"
        case .sslError: "SSL certificate validation failed"
        case .cancelled: "Request was cancelled"
        case .storage: "Storage operation failed"
        case .connectionClosed(let code, let reason):
            "WebSocket closed with code \(code)\(reason.map { ": \($0)" } ?? "")"
        case .unknown: "Unknown error"
        }
    }
}

// MARK: - Init from other errors
extension APIError {
    init(from networkError: TransportError, body: Failure? = nil) {
        switch networkError {
        case .url(let urlError):
            switch urlError.code {
            case .timedOut: self = .timedOut
            case .cancelled: self = .cancelled
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: self = .noConnection
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted: self = .sslError
            case .cannotFindHost, .dnsLookupFailed: self = .serverUnreachable
            default: self = .unknown
            }
        case .noResponse: self = .noResponse
        case .invalidURL: self = .invalidURL
        case .http(let status, _): self = .http(status: status, body: body)
        case .cancelled: self = .cancelled
        default: self = .unknown
        }
    }

    init(from authError: AuthError) {
        switch authError {
        case .missingToken: self = .missingToken
        case .invalidCredentials: self = .http(status: .unauthorized)
        case .failedToRefreshToken: self = .tokenExpired
        case .cancelled: self = .cancelled
        }
    }

    init(from fileError: FileError) {
        switch fileError {
        case .invalidTargetURL, .removeFailed, .copyFailed: self = .storage
        }
    }

    init(from mapperError: MapperError) {
        switch mapperError {
        case .unsuported: self = .unsupportedType
        case .incorrect: self = .typeMismatch
        case .encoding: self = .encode
        case .decoding: self = .decode
        }
    }

    init(from wsError: WebSocketError) {
        switch wsError {
        case .closed(let code, let reason):
            self = .connectionClosed(code: code.rawValue, reason: reason)
        case .unexpectedDisconnection:
            self = .connectionClosed(code: 1006, reason: nil)
        case .network(let urlError):
            self = APIError(from: TransportError.url(urlError))
        case .sendFailed:
            self = .connectionClosed(code: 1006, reason: "send failed")
        case .pingFailed:
            self = .connectionClosed(code: 1006, reason: "ping timeout")
        }
    }

    /// Unified initializer that dispatches any error to the appropriate conversion.
    init(error: Error, decodeBody: ((Data) -> Failure?)? = nil) {
        switch error {
        case let e as APIError<Failure>: self = e
        case let e as TransportError:    self = APIError(from: e, body: e.body.flatMap { decodeBody?($0) })
        case let e as URLError:          self = APIError(from: TransportError.url(e))
        case let e as WebSocketError:    self = APIError(from: e)
        case let e as AuthError:         self = APIError(from: e)
        case let e as FileError:         self = APIError(from: e)
        case let e as MapperError:       self = APIError(from: e)
        default:                         self = .unknown
        }
    }
}

// MARK: - Equatable
extension APIError: Equatable {
    public static func == (lhs: APIError<Failure>, rhs: APIError<Failure>) -> Bool {
        lhs.id == rhs.id
    }
}

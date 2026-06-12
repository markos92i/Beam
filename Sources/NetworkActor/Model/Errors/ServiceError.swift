//
//  ServiceError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation

public enum ServiceError<Failure: Sendable>: Error, Identifiable {
    // Serialización
    case encode
    case decode
    case unsupportedType
    case typeMismatch

    // Request inválida
    case invalidURL
    case invalidFormat
    case missingUploadData
    case missingToken
    case tokenExpired

    // Red
    case noConnection
    case timedOut
    case serverUnreachable
    case sslError
    case noResponse

    // Respuesta del servidor
    case http(status: HTTPStatus, body: Failure? = nil)

    // Sistema
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

        case .http(let code, _): code.rawValue

        case .storage: 90
        case .cancelled: 91
        case .unknown: 99
        }
    }
}

// MARK: - Properties
extension ServiceError {
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

    public var name: String {
        switch self {
        case .http(let status, _): "http(\(status.rawValue)) \(status.name)"
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
        case .sslError: "􀞡"
        case .timedOut: "􀐫"
        case .noConnection: "􀤆"
        case .cancelled: "􀁠"
        case .storage: "􁘥"
        case .missingUploadData: "􀈂"
        case .unknown: "􀁜"
        }
    }

    var detail: String? {
        switch self {
        case .invalidURL: "Could not construct a valid URL from host and path"
        case .invalidFormat: "The response format is not valid"
        case .noResponse: "Server did not return an HTTP response"
        case .missingUploadData: "Upload body is empty — no data to send"
        default: nil
        }
    }
}

// MARK: - Init from other errors
extension ServiceError {
    init(from networkError: ClientError, body: Failure? = nil) {
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

    init(from serializerError: SerializerError) {
        switch serializerError {
        case .unsuported: self = .unsupportedType
        case .incorrect: self = .typeMismatch
        case .encoding: self = .encode
        case .decoding: self = .decode
        }
    }
}

// MARK: - Equatable
extension ServiceError: Equatable {
    public static func == (lhs: ServiceError<Failure>, rhs: ServiceError<Failure>) -> Bool {
        lhs.id == rhs.id
    }
}

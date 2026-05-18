//
//  ServiceError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation

public enum ServiceError<Failure: Sendable>: Error, Identifiable {
    case encode
    case decode
    case storage
    case invalidURL
    case invalidFormat
    case noResponse
    
    case cancelled
    case timedOut
    case noConnection
    case serverUnreachable
    case sslError
    case unknown

    // Errores HTTP con valor asociado genérico (el Dto de error del backend)
    case badRequest(Failure?)
    case unauthorized(Failure?)
    case forbidden(Failure?)
    case notFound(Failure?)
    case conflict(Failure?)
    case serverError(Failure?)
    
    case unexpectedCode(statusCode: Int, body: Failure?)

    // MARK: - Identifiable Compliance
    public var id: Int {
        switch self {
        case .encode: 0
        case .decode: 1
        case .storage: 2
        case .invalidURL: 3
        case .invalidFormat: 4
        case .noResponse: 5
        
        case .cancelled: 8
        case .timedOut: 9
        case .noConnection: 10
        case .serverUnreachable: 11
        case .sslError: 12
        case .unknown: 99

        case .badRequest: 400
        case .unauthorized: 401
        case .forbidden: 403
        case .notFound: 404
        case .conflict: 409
        case .serverError: 500
            
        case .unexpectedCode(let statusCode, _): statusCode
        }
    }
}

extension ServiceError {
    init(from networkError: NetworkError, serializer: Serializer) {
        switch networkError {
        case .http(let statusCode, let data):
            let decodedBody: Failure? = data.flatMap { try? serializer.decode(data: $0) }
            switch statusCode {
            case 400: self = .badRequest(decodedBody)
            case 401: self = .unauthorized(decodedBody)
            case 403: self = .forbidden(decodedBody)
            case 404: self = .notFound(decodedBody)
            case 409: self = .conflict(decodedBody)
            case 500...599: self = .serverError(decodedBody)
            default: self = .unexpectedCode(statusCode: statusCode, body: decodedBody)
            }
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
        default: self = .unknown
        }
    }
    
    init(from authError: AuthError) {
        switch authError {
        case .missingToken, .invalidCredentials, .failedToRefreshToken:
            self = .unauthorized(nil)
        case .unknown:
            self = .unknown
        }
    }
    
    init(from fileError: FileError) {
        switch fileError {
        case .invalidTargetURL, .removeFailed, .copyFailed:
            self = .storage
        }
    }
    
    init(from serializerError: SerializerError) {
        switch serializerError {
        case .encoding: self = .encode
        case .decoding: self = .decode
        }
        
    }
}

// MARK: - Equatable Compliance
extension ServiceError: Equatable {
    public static func == (lhs: ServiceError<Failure>, rhs: ServiceError<Failure>) -> Bool {
        lhs.id == rhs.id
    }
}

extension ServiceError: CustomNSError {
    public static var errorDomain: String { Bundle.main.bundleIdentifier ?? "network.actor" }
    
    public var errorCode: Int { id }
    
    public var errorUserInfo: [String: Any] {
        [
            NSLocalizedDescriptionKey: "\(id): \(self)",
            NSLocalizedFailureReasonErrorKey: "description"
        ]
    }
}

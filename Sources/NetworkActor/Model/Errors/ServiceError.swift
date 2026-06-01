//
//  ServiceError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation

public enum ServiceError<Failure: Sendable>: Error, Identifiable {
    case unsuported
    case incorrect
    case encode
    case decode
    case storage
    case invalidURL
    case invalidFormat
    case missingUploadData
    case missingToken
    case noResponse
    
    case cancelled
    case timedOut
    case noConnection
    case serverUnreachable
    case sslError
    case unknown

    case http(status: HTTPStatus, body: Failure?)

    // MARK: - Identifiable Compliance
    public var id: Int {
        switch self {
        case .unsuported: 0
        case .incorrect: 1
        case .encode: 2
        case .decode: 3
        case .storage: 4
        case .invalidURL: 5
        case .invalidFormat: 6
        case .missingUploadData: 7
        case .missingToken: 8
        case .noResponse: 9
            
        case .cancelled: 80
        case .timedOut: 81
        case .noConnection: 82
        case .serverUnreachable: 83
        case .sslError: 84
            
        case .unknown: 99

        case .http(let code, _): code.rawValue
        }
    }
}

extension ServiceError {
    public var status: HTTPStatus? {
        if case .http(let status, _) = self { status } else { nil }
    }

    public var body: Failure? {
        if case .http(_, let body) = self { body } else { nil }
    }
}

extension ServiceError {
    init(from networkError: NetworkError, body: Failure? = nil) {
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
        default: self = .unknown
        }
    }
    
    init(from authError: AuthError) {
        switch authError {
        case .missingToken: self = .missingToken
        case .invalidCredentials: self = .http(status: .unauthorized, body: nil)
        case .failedToRefreshToken: self = .http(status: .unauthorized, body: nil)
        case .unknown: self = .unknown
        }
    }
    
    init(from fileError: FileError) {
        switch fileError {
        case .invalidTargetURL, .removeFailed, .copyFailed: self = .storage
        }
    }
    
    init(from serializerError: SerializerError) {
        switch serializerError {
        case .unsuported: self = .encode
        case .incorrect: self = .encode
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
        ]
    }
}

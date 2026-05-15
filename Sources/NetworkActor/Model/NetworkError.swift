//
//  NetworkError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

public enum NetworkError: Error {
    case invalidURL
    case noResponse
    case invalidTargetURL
    case removeFailed(Error)
    case copyFailed(Error)
    case url(Error, code: URLError.Code)
    case http(code: Int, data: Data?)
    case unknown
    
    public init(fileError: FileError) {
        switch fileError {
        case .invalidTargetURL: self = .invalidTargetURL
        case .removeFailed(let error): self = .removeFailed(error)
        case .copyFailed(let error): self = .copyFailed(error)
        }
    }
    /*
    public init(statusCode: Int, body: Data?) {
        self.body = body
        
        switch statusCode {
        case 400: self.type = .badRequest
        case 401: self.type = .unauthorized
        case 403: self.type = .forbidden
        case 404: self.type = .notFound
        case 409: self.type = .conflict
        case 500...599: self.type = .serverError
        default: self.type = .unexpectedCode
        }
    }
    
    public init(urlError: URLError) {
        self.body = nil
        
        switch urlError.code {
        case .timedOut:
            self.type = .timedOut
        case .cancelled:
            self.type = .canceled
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            self.type = .noConnection
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted:
            self.type = .sslError
        case .cannotFindHost, .dnsLookupFailed:
            self.type = .serverError
        default:
            self.type = .unknown
        }
    }
     */
}

//
//  TransportError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

public enum TransportError: Error, LoggableError {
    case invalidURL
    case invalidResume
    case noResponse
    case cancelled
    case url(URLError)
    case http(status: HTTPStatus, body: Data?)
    case unknown(Error)

    var description: String? {
        switch self {
        case .invalidURL: "The URL is invalid"
        case .invalidResume: "The resume data is missing or is invalid"
        case .noResponse: "Didnt receive response from server"
        case .cancelled: "Task cancelled"
        case .url(let error): error.localizedDescription
        case .http(let status, _): "HTTP: \(status.rawValue)"
        case .unknown(let error): error.localizedDescription
        }
    }

    public var status: HTTPStatus {
        if case .http(let status, _) = self { status } else { .undefined }
    }

    var body: Data? {
        if case .http(_, let body) = self { body } else { nil }
    }

    var logDescription: String {
        switch self {
        case .url(let error):
            return error.localizedDescription
        case .unknown(let error):
            return error.localizedDescription
        default:
            return description ?? ""
        }
    }

    var isRetryable: Bool {
        switch self {
        case .url(let error):
            switch error.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet: true
            default: false
            }
        case .http(let status, _): status.type == .serverError || status == .unauthorized
        default: false
        }
    }
}

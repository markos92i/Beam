//
//  ClientError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

public enum ClientError: Error, InfoError {
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
    
    var info: [String: any Sendable] {
        ["ResponseBody": String(data: body ?? Data(), encoding: .utf8)?.prefix(2000) ?? ""]
    }

    var underlyingDescription: String? {
        switch self {
        case .url(let error): error.localizedDescription
        case .unknown(let error): error.localizedDescription
        default: nil
        }
    }

    var logLines: (subtitle: String?, detail: [String]) {
        if let body, let text = String(data: body, encoding: .utf8) {
            return (nil, ["􁒡 \(text.prefix(200))"])
        }
        if let desc = underlyingDescription {
            return (nil, ["􀺾 \(desc)"])
        }
        return (nil, [])
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



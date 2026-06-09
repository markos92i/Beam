//
//  ClientError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

public enum ClientError: Error {
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
    
    var info: [String: Any] {
        ["ResponseBody": String(data: body ?? Data(), encoding: .utf8)?.prefix(2000) ?? ""]
    }
}

extension ClientError: CustomNSError {
    public static var errorDomain: String { "network.ClientError" }
        
    public var errorCode: Int { status.rawValue }

    public var errorUserInfo: [String: Any] {
        [
            NSLocalizedDescriptionKey: "ClientError: \(self)", // Main Message
            NSLocalizedFailureErrorKey: "Status: \(status.rawValue)" // Extras
        ].merging(info) { $1 }
    }
}

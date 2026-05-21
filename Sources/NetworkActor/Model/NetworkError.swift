//
//  NetworkError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

public enum NetworkError: Error {
    case invalidURL
    case invalidResume
    case noResponse
    case cancelled
    case url(URLError)
    case http(code: Int, body: Data?)
    case unknown(Error)
    
    var description: String? {
        switch self {
        case .invalidURL: "The URL is invalid"
        case .invalidResume: "The resume data is missing or is invalid"
        case .noResponse: "Didnt receive response from server"
        case .cancelled: "Operation was cancelled"
        case .url(let error): error.localizedDescription
        case .http(let code, _): HTTPStatus(rawValue: code)?.description
        case .unknown(let error): error.localizedDescription
        }
    }

    var statusCode: Int {
        if case .http(let code, _) = self { code } else { -1000 }
    }
    
    var body: Data? {
        if case .http(_, let body) = self { body } else { nil }
    }
    
    var info: [String: Any] {
        ["ResponseBody": String(data: body ?? Data(), encoding: .utf8)?.prefix(2000) ?? ""]
    }
}

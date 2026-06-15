//
//  ClientError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

public enum ClientError: Error, LoggableError {
    case invalidURL
    case invalidResume
    case noResponse
    case cancelled
    case url(URLError)
    case http(status: HTTPStatus, body: Data?)
    case unknown(Error)
    case webSocket(URLSessionWebSocketTask.CloseCode, Data?)

    var description: String? {
        switch self {
        case .invalidURL: "The URL is invalid"
        case .invalidResume: "The resume data is missing or is invalid"
        case .noResponse: "Didnt receive response from server"
        case .cancelled: "Task cancelled"
        case .url(let error): error.localizedDescription
        case .http(let status, _): "HTTP: \(status.rawValue)"
        case .unknown(let error): error.localizedDescription
        case .webSocket(let code, _): "WebSocket closed with code: \(code.rawValue)"
        }
    }

    public var status: HTTPStatus {
        if case .http(let status, _) = self { status } else { .undefined }
    }

    var body: Data? {
        if case .http(_, let body) = self { body } else { nil }
    }

    var info: [String: any Sendable] {
        switch self {
        case .webSocket(let code, let reason):
            let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return [
                "CloseCode": code.rawValue,
                "Reason": String(reasonString.prefix(2000))
            ]
        default:
            return ["ResponseBody": String(data: body ?? Data(), encoding: .utf8)?.prefix(2000) ?? ""]
        }
    }

    var logLines: (subtitle: String?, detail: [String]) {
        switch self {
        case .webSocket(let code, let reason):
            let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
            let detail = reasonString.map { "􀺾 Close code \(code.rawValue): \($0)" } ?? "􀺾 Close code \(code.rawValue)"
            return (nil, [detail])
        case .url(let error):
            return (nil, ["􀺾 \(error.localizedDescription)"])
        case .unknown(let error):
            return (nil, ["􀺾 \(error.localizedDescription)"])
        default:
            return (nil, [])
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
        case .webSocket: true
        default: false
        }
    }

    // MARK: - WebSocket

    /// Maps a WebSocket receive/send error to the appropriate `ClientError`.
    /// - URLErrors → `.url()` (network-level, same treatment as HTTP)
    /// - Everything else → `.webSocket(.abnormalClosure)` (socket dropped without close frame)
    static func from(webSocketError error: Error) -> ClientError? {
        if let urlError = error as? URLError {
            return .url(urlError)
        }
        return .webSocket(.abnormalClosure, nil)
    }

    /// Creates a `ClientError` from a WebSocket close code.
    /// Returns `nil` for `.normalClosure` (1000) since that's a clean shutdown, not an error.
    static func from(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) -> ClientError? {
        if closeCode == .normalClosure { return nil }
        return .webSocket(closeCode, reason)
    }
}

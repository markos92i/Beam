//
//  EndpointFailure.swift
//  Beam
//

import Foundation

/// A call that failed and won't be retried, as monitors see it.
public struct EndpointFailure: Sendable {
    /// The final error, without its decoded body.
    public let error: APIError<Void>
    /// The last request sent, without credentials; `nil` if the call failed before sending.
    public let request: URLRequest?
    /// The last response received, if any.
    public let response: Response?

    let method: HTTPMethod
    let host: String
    let path: String
    let pathTemplate: String
    let attempt: Int

    /// Cancelled, offline or timed out: not worth reporting.
    public var isExpected: Bool { error.isExpected }

    /// The crash report for this failure, without bodies.
    public var report: ErrorReport { report(including: []) }

    /// Only text bodies are added, truncated to 1 kB; they may contain personal data.
    public func report(including details: Set<ErrorReport.Detail>) -> ErrorReport {
        var info: [String: String] = [
            "Method": method.description,
            "Host": host,
            "Path": path,
            "Attempt": "\(attempt)",
            "ErrorDetail": error.logDescription,
        ]
        // Raw code: an unknown one is `.undefined` in the error.
        if let response { info["Status"] = "\(response.http.statusCode)" }
        if case .http(_, let body, _) = error, let decodingError = body.decodingError {
            info["ErrorBodyDecoding"] = Self.text(Data(decodingError.logDescription.utf8))
        }

        for detail in details {
            switch detail {
            case .responseBody:
                info["ResponseBody"] = response.flatMap(Self.responseText)
            case .requestBody(let redacting):
                info["RequestBody"] = request.flatMap { Self.requestText($0, redacting: redacting) }
            }
        }

        return ErrorReport(
            domain: "\(method) \(pathTemplate) — \(error.name)",
            code: error.id,
            info: info
        )
    }

    // MARK: - Bodies

    /// Crashlytics keeps up to 1 kB per value.
    private static let maxValueBytes = 1024

    private static func responseText(_ response: Response) -> String? {
        guard response.contentType?.isText == true else { return nil }
        return response.errorBody.flatMap(text)
    }

    private static func requestText(_ request: URLRequest, redacting keys: Set<String>) -> String? {
        guard let body = request.httpBody, request.value(forHTTPHeaderField: "Content-Type").map(ContentType.init(rawHeader:))?.isText == true else { return nil }
        return text(keys.isEmpty ? body : JSONRedaction.redact(keys, in: body))
    }

    private static func text(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return String(decoding: data.prefix(maxValueBytes), as: UTF8.self)
    }
}

// MARK: - ErrorReport

/// A crash report for a failed call; `domain` uses the route template so occurrences group together.
public struct ErrorReport: Sendable {
    /// Bodies a report can include.
    public enum Detail: Hashable, Sendable {
        /// The last response body.
        case responseBody
        /// The request body, with JSON values of the given keys (at any depth) replaced.
        case requestBody(redacting: Set<String> = [])
    }

    public let domain: String
    public let code: Int
    public let info: [String: String]

    /// The report as an `NSError`, which crash reporters group by domain and code.
    public var error: NSError {
        NSError(domain: domain, code: code, userInfo: info.merging([NSLocalizedDescriptionKey: info["ErrorDetail"] ?? domain]) { $1 })
    }
}

// MARK: - JSON Redaction

enum JSONRedaction {
    private enum Value: Codable {
        case object([String: Value])
        case array([Value])
        case string(String)
        case number(Double)
        case bool(Bool)
        case null

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([Value].self) { self = .array(value) }
            else { self = .object(try container.decode([String: Value].self)) }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .object(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .null: try container.encodeNil()
            }
        }

        func redacting(_ keys: Set<String>) -> Value {
            switch self {
            case .object(let object):
                .object(object.reduce(into: [:]) { result, entry in
                    result[entry.key] = keys.contains(entry.key) ? .string("•••") : entry.value.redacting(keys)
                })
            case .array(let array):
                .array(array.map { $0.redacting(keys) })
            default:
                self
            }
        }
    }

    /// Empty when the body isn't JSON: it can't be redacted safely.
    static func redact(_ keys: Set<String>, in data: Data) -> Data {
        guard let value = try? JSONDecoder().decode(Value.self, from: data),
              let redacted = try? JSONEncoder().encode(value.redacting(keys)) else {
            return Data()
        }
        return redacted
    }
}

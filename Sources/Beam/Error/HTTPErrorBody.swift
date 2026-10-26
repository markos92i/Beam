//
//  HTTPErrorBody.swift
//  Beam
//

import Foundation

/// An HTTP error response body: decoded when it matches the route's error type, always kept raw.
public struct HTTPErrorBody<Failure: Sendable>: Sendable {
    /// The body decoded as the route's error type, if it decodes.
    public let value: Failure?
    /// The body as sent: whole in data calls, up to 64 KB for downloads and streams.
    public let data: Data?
    /// Why a non-empty ``data`` didn't decode into ``value``.
    public let decodingError: CodingError?

    public init(_ value: Failure? = nil, data: Data? = nil, decodingError: CodingError? = nil) {
        self.value = value
        self.data = data
        self.decodingError = decodingError
    }

    /// No body.
    public static var empty: Self { Self() }

    /// ``data`` as UTF-8 text.
    public var text: String? {
        data.flatMap { String(data: $0, encoding: .utf8) }
    }

    var withoutValue: HTTPErrorBody<Void> {
        HTTPErrorBody<Void>(nil, data: data, decodingError: decodingError)
    }

    static var limit: Int { 64 * 1024 }
}

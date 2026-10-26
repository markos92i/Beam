//
//  FinishedTransfer.swift
//  Beam
//

import Foundation

/// A background transfer that finished with nobody awaiting it, e.g. after a relaunch.
/// It comes validated, but skips the route's interceptors and decoding.
public struct FinishedTransfer: Sendable {
    /// The id given to `start(id:)`; `nil` for a task Beam didn't create.
    public let id: String?

    /// The route's method.
    public let method: HTTPMethod?

    /// The route's path template, e.g. `/{userID}/documents`.
    public let pathTemplate: String?

    /// The original request, without credentials.
    public let request: URLRequest?

    /// The HTTP response, if one arrived.
    public let response: HTTPURLResponse?

    /// The response body of an upload (also a failed one) or of a download rejected with an HTTP status.
    public let body: Data?

    public let outcome: Outcome

    let storeID: String?

    /// When a ``Session/finished(until:)`` stream ends.
    public enum Until: Sendable {
        /// When iOS has delivered the events it relaunched the app for, as `.backgroundTask(.urlSession(…))` needs.
        case eventsDelivered
        /// When the iterating task is cancelled, e.g. a screen's `.task`.
        case cancelled
    }

    public enum Outcome: Sendable {
        /// The upload succeeded, with the response body.
        case uploaded(Data)
        /// The download succeeded; the file stays until ``Session/remove(_:)``, so move it to keep it.
        case downloaded(URL)
        /// Transport, HTTP status (`.http(status:)`) or storage failure.
        case failed(APIError<Void>)
    }

    /// Decodes ``body`` as JSON; `.typeMismatch` when there is none.
    /// `json` is required: the route's settings don't survive a relaunch.
    public func decode<Value: Decodable & SendableMetatype>(_ type: Value.Type = Value.self, json: JSONCoding) throws(CodingError) -> Value {
        try decode(using: .json, json: json)
    }

    /// Decodes ``body`` with any ``BodyDecoder``, as a route would.
    public func decode<Value>(using decoding: BodyDecoder<Value>, json: JSONCoding) throws(CodingError) -> Value {
        guard let body else { throw .typeMismatch }
        return try decoding.decode(body, with: json)
    }
}

//
//  HTTPBody.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 18/05/2026.
//

import Foundation

/// Represents the body of an outgoing HTTP request.
///
/// Each case carries its payload and determines the `Content-Type` header
/// via ``contentType``. Use ``encode(with:)`` to serialize to raw `Data`.
public enum HTTPBody: Sendable {
    /// JSON-encoded body. Accepts any `Encodable & Sendable` value.
    /// Sets `Content-Type: application/json; charset=UTF-8`.
    case json(any Encodable & Sendable)

    /// Raw data with an explicit content type.
    /// Defaults to `application/octet-stream` if no content type is specified.
    case data(Data, contentType: ContentType = .data)

    /// Multipart form data for file uploads.
    /// Sets `Content-Type: multipart/form-data; boundary=...`.
    case multipart(MultipartForm)

    /// URL form-encoded body (`key=value&key2=value2`).
    /// Sets `Content-Type: application/x-www-form-urlencoded`.
    /// Values are percent-encoded automatically.
    case formURLEncoded([URLQueryItem])
}

extension HTTPBody {
    /// The Content-Type this body represents.
    public var contentType: ContentType {
        switch self {
        case .json: .json()
        case .data(_, let contentType): contentType
        case .multipart(let form): .multipart(boundary: form.boundary)
        case .formURLEncoded: .urlEncoded
        }
    }

    /// Serializes the body to raw Data.
    public func encode(with mapper: MapperProtocol) throws -> Data {
        switch self {
        case .json(let value):
            try mapper.encode(value)
        case .data(let raw, _):
            raw
        case .multipart(let form):
            try form.body
        case .formURLEncoded(let items):
            items.formEncoded()
        }
    }
}

// MARK: - URL Form Encoding

extension Array where Element == URLQueryItem {
    /// Encodes query items as `application/x-www-form-urlencoded` Data.
    func formEncoded() -> Data {
        var components = URLComponents()
        components.queryItems = self
        let encoded = components.percentEncodedQuery ?? ""
        return Data(encoded.utf8)
    }
}

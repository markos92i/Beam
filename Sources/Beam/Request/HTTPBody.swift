//
//  HTTPBody.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 18/05/2026.
//

import Foundation

/// The body of an outgoing request, encoded once per call with the API's `JSONCoding`.
public enum HTTPBody: Sendable {
    case json(any Encodable & Sendable)

    case data(Data, contentType: ContentType = .data)

    case multipart(MultipartForm)

    /// Values are percent-encoded automatically.
    case formURLEncoded([URLQueryItem])
}

extension HTTPBody {
    /// The `Content-Type` this body sends.
    public var contentType: ContentType {
        switch self {
        case .json: .json
        case .data(_, let contentType): contentType
        case .multipart(let form): .multipart(boundary: form.boundary)
        case .formURLEncoded: .urlEncoded
        }
    }
}

// MARK: - URL Form Encoding

extension Array where Element == URLQueryItem {
    func formEncoded() -> Data {
        var components = URLComponents()
        components.queryItems = self
        let encoded = components.percentEncodedQuery ?? ""
        return Data(encoded.utf8)
    }
}

//
//  HTTPBody.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 18/05/2026.
//

import Foundation

public enum HTTPBody: Sendable {
    case data(Data)
    case dictionary([String: Encodable & Sendable])
    case json(Sendable)
    case multipart(MultipartForm)
}

extension HTTPBody {
    public func data(with serializer: SerializerProtocol) throws -> Data {
        switch self {
        case .data(let data): data
        case .dictionary(let dict): try serializer.encode(DictionaryWrapper(dictionary: dict))
        case .json(let codable): try serializer.encode(codable)
        case .multipart(let multipart): try multipart.body
        }
    }
}

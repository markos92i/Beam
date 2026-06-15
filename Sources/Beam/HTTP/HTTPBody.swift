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

// MARK: - Dictionary Encoding Support

struct DictionaryWrapper: Encodable & Sendable {
    let dictionary: [String: Encodable & Sendable]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        for (key, value) in dictionary {
            guard let codingKey = DynamicCodingKeys(stringValue: key) else { continue }
            try container.encode(value, forKey: codingKey)
        }
    }

    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

//
//  DictionaryWrapper.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 31/05/2026.
//

import Foundation

public struct DictionaryWrapper: Encodable & Sendable {
    public let dictionary: [String: Encodable & Sendable]

    public func encode(to encoder: Encoder) throws {
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

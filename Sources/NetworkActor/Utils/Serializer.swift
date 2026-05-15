//
//  Serializer.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//


import Foundation
import SwiftUI

public struct Serializer: Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(encoder: JSONEncoder, decoder: JSONDecoder) {
        self.encoder = encoder
        self.decoder = decoder
    }

    public func encode<Value>(_ value: Value) throws -> Data? {
        switch value {
        case let value as Data: value
        case let value as String: value.data(using: .utf8)
        case let value as Codable: try encoder.encode(value)
        default: nil
        }
    }

    public func decode<Value>(data: Data) throws -> Value? {
        switch Value.self {
        case is Data.Type: data as? Value
        case is Bool.Type: Bool(String(data: data, encoding: .utf8) ?? "false") as? Value
        case is String.Type: String(data: data, encoding: .utf8) as? Value
        case let type as Codable.Type: try decoder.decode(type, from: data) as? Value
        case is UIImage.Type: UIImage(data: data) as? Value
        case is Void.Type: () as? Value
        default: nil
        }
    }
}

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
        case let value as Data:
            return value
        case let value as String:
            return value.data(using: .utf8)
        case let value as Codable:
            do {
                return try encoder.encode(value)
            } catch let error as EncodingError {
                throw SerializerError(encodingError: error)
            } catch {
                throw error
            }
        default:
            return nil
        }
    }
    
    public func decode<Value>(data: Data) throws -> Value? {
        switch Value.self {
        case is Data.Type:
            return data as? Value
        case is Bool.Type:
            return Bool(String(data: data, encoding: .utf8) ?? "false") as? Value
        case is String.Type:
            return String(data: data, encoding: .utf8) as? Value
        case let type as Codable.Type:
            do {
                return try decoder.decode(type, from: data) as? Value
            } catch let error as DecodingError {
                throw SerializerError(decodingError: error)
            } catch {
                throw error
            }
        case is UIImage.Type:
            return UIImage(data: data) as? Value
        case is Void.Type:
            return () as? Value
        default:
            return nil
        }
    }
}

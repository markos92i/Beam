//
//  Serializer.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct Serializer: SerializerProtocol {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(encoder: JSONEncoder = .iso8601, decoder: JSONDecoder = .iso8601) {
        self.encoder = encoder
        self.decoder = decoder
    }
    
    public func encode<Value>(_ value: Value) throws -> Data {
        switch value {
        case let data as Data:
            return data
            
        case let string as String:
            guard let data = string.data(using: .utf8) else { throw SerializerError.incorrect }
            return data
            
        case let dictionary as DictionaryWrapper:
            do {
                return try encoder.encode(dictionary)
            } catch let error as EncodingError {
                throw SerializerError(encodingError: error)
            } catch {
                throw error
            }

        case let codable as Codable:
            do {
                return try encoder.encode(codable)
            } catch let error as EncodingError {
                throw SerializerError(encodingError: error)
            } catch {
                throw error
            }
            
        default:
            throw SerializerError.unsuported
        }
    }
    
    /// Deserializa Data pura al tipo genérico inferido. Garantiza el resultado o lanza excepción.
    public func decode<Value>(data: Data) throws -> Value {
        switch Value.self {
        case is Data.Type:
            guard let result = data as? Value else { throw SerializerError.incorrect }
            return result
            
        case is Bool.Type:
            guard let string = String(data: data, encoding: .utf8), let result = Bool(string) as? Value else { throw SerializerError.incorrect }
            return result
            
        case is String.Type:
            guard let result = String(data: data, encoding: .utf8) as? Value else { throw SerializerError.incorrect }
            return result
            
        case let type as Codable.Type:
            do {
                guard let result = try decoder.decode(type, from: data) as? Value else { throw SerializerError.incorrect }
                return result
            } catch let error as DecodingError {
                throw SerializerError(decodingError: error)
            } catch {
                throw error
            }
            
        #if canImport(UIKit)
        case is UIImage.Type:
            guard let result = UIImage(data: data) as? Value else { throw SerializerError.incorrect }
            return result
        #endif
            
        case is Void.Type:
            guard let result = () as? Value else { throw SerializerError.incorrect }
            return result
            
        default:
            throw SerializerError.unsuported
        }
    }
}

extension JSONEncoder {
    public static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    public static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

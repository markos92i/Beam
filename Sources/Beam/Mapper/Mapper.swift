//
//  Mapper.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/05/2026.
//

import Foundation

public struct Mapper: MapperProtocol {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(encoder: JSONEncoder = .iso8601, decoder: JSONDecoder = .iso8601) {
        self.encoder = encoder
        self.decoder = decoder
    }

    public func encode(_ value: some Encodable) throws(MapperError) -> Data {
        if let raw = value as? any RawEncodable {
            return try raw.encode()
        }

        do {
            return try encoder.encode(value)
        } catch let error as EncodingError {
            throw MapperError(encodingError: error)
        } catch {
            throw .incorrect
        }
    }

    /// Deserializes raw Data into the inferred generic type.
    public func decode<Value>(data: Data) throws(MapperError) -> Value {
        if Value.self is Void.Type, let result = () as? Value {
            return result
        }

        if let raw = Value.self as? any RawDecodable.Type {
            do {
                let decoded = try raw.decode(from: data)
                guard let result = decoded as? Value else { throw MapperError.incorrect }
                return result
            } catch let error as MapperError { throw error }
            catch { throw .incorrect }
        }

        guard let type = Value.self as? any Decodable.Type else { throw .unsuported }
        do {
            guard let result = try decoder.decode(type, from: data) as? Value else { throw MapperError.incorrect }
            return result
        } catch let error as MapperError {
            throw error
        } catch let error as DecodingError {
            throw MapperError(decodingError: error)
        } catch {
            throw .incorrect
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

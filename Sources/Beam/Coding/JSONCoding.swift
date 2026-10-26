//
//  JSONCoding.swift
//  Beam
//
//  How JSON bodies are encoded and decoded: the strategies of Apple's JSONEncoder
//  and JSONDecoder, as a value in `RequestConfig`.
//

import Foundation

/// Apple's `JSONEncoder` / `JSONDecoder` strategies as a value, with Apple's defaults.
/// Set per API in ``RequestConfig``, or per route with the route macros' `json:`.
public struct JSONCoding: Sendable {
    // MARK: Encoding

    public var outputFormatting: JSONEncoder.OutputFormatting
    public var dateEncoding: JSONEncoder.DateEncodingStrategy
    public var dataEncoding: JSONEncoder.DataEncodingStrategy
    public var floatEncoding: JSONEncoder.NonConformingFloatEncodingStrategy
    public var keyEncoding: JSONEncoder.KeyEncodingStrategy

    // MARK: Decoding

    public var dateDecoding: JSONDecoder.DateDecodingStrategy
    public var dataDecoding: JSONDecoder.DataDecodingStrategy
    public var floatDecoding: JSONDecoder.NonConformingFloatDecodingStrategy
    public var keyDecoding: JSONDecoder.KeyDecodingStrategy
    public var allowsJSON5: Bool
    public var assumesTopLevelDictionary: Bool

    public init(
        outputFormatting: JSONEncoder.OutputFormatting = [],
        dateEncoding: JSONEncoder.DateEncodingStrategy = .deferredToDate,
        dataEncoding: JSONEncoder.DataEncodingStrategy = .base64,
        floatEncoding: JSONEncoder.NonConformingFloatEncodingStrategy = .throw,
        keyEncoding: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys,
        dateDecoding: JSONDecoder.DateDecodingStrategy = .deferredToDate,
        dataDecoding: JSONDecoder.DataDecodingStrategy = .base64,
        floatDecoding: JSONDecoder.NonConformingFloatDecodingStrategy = .throw,
        keyDecoding: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        allowsJSON5: Bool = false,
        assumesTopLevelDictionary: Bool = false
    ) {
        self.outputFormatting = outputFormatting
        self.dateEncoding = dateEncoding
        self.dataEncoding = dataEncoding
        self.floatEncoding = floatEncoding
        self.keyEncoding = keyEncoding
        self.dateDecoding = dateDecoding
        self.dataDecoding = dataDecoding
        self.floatDecoding = floatDecoding
        self.keyDecoding = keyDecoding
        self.allowsJSON5 = allowsJSON5
        self.assumesTopLevelDictionary = assumesTopLevelDictionary
    }

    /// Apple's defaults.
    public static var `default`: JSONCoding { JSONCoding() }

    /// Apple's defaults, with ISO 8601 dates both ways.
    public static var iso8601: JSONCoding { JSONCoding(dateEncoding: .iso8601, dateDecoding: .iso8601) }

    // MARK: - Coding

    /// Encodes `value` as JSON.
    public func encode(_ value: some Encodable) throws(CodingError) -> Data {
        do {
            return try encoder.encode(value)
        } catch let error as EncodingError {
            throw CodingError(encodingError: error)
        } catch {
            // A custom `encode(to:)` threw its own error.
            let context = EncodingError.Context(codingPath: [], debugDescription: "\(error)", underlyingError: error)
            throw CodingError(encodingError: .invalidValue(value, context))
        }
    }

    /// Decodes JSON into `Value`.
    public func decode<Value: Decodable>(_ type: Value.Type = Value.self, from data: Data) throws(CodingError) -> Value {
        do {
            return try decoder.decode(Value.self, from: data)
        } catch let error as DecodingError {
            throw CodingError(decodingError: error)
        } catch {
            // A custom `init(from:)` threw its own error.
            let context = DecodingError.Context(codingPath: [], debugDescription: "\(error)", underlyingError: error)
            throw CodingError(decodingError: .dataCorrupted(context))
        }
    }

    // A new encoder and decoder per use: cheap, and never shared between calls.

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = dateEncoding
        encoder.dataEncodingStrategy = dataEncoding
        encoder.nonConformingFloatEncodingStrategy = floatEncoding
        encoder.keyEncodingStrategy = keyEncoding
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecoding
        decoder.dataDecodingStrategy = dataDecoding
        decoder.nonConformingFloatDecodingStrategy = floatDecoding
        decoder.keyDecodingStrategy = keyDecoding
        decoder.allowsJSON5 = allowsJSON5
        decoder.assumesTopLevelDictionary = assumesTopLevelDictionary
        return decoder
    }
}

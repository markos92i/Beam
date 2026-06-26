//
//  RawCodable.swift
//  Beam
//
//  Types that can encode/decode directly from raw Data without JSON serialization.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Protocols

/// A type that knows how to decode itself from raw `Data` without JSON.
protocol RawDecodable {
    static func decode(from data: Data) throws(MapperError) -> Self
}

/// A type that knows how to encode itself to raw `Data` without JSON.
protocol RawEncodable {
    func encode() throws(MapperError) -> Data
}

/// A type that supports both raw encoding and decoding.
typealias RawCodable = RawDecodable & RawEncodable

// MARK: - Data

extension Data: RawCodable {
    static func decode(from data: Data) throws(MapperError) -> Data { data }
    func encode() throws(MapperError) -> Data { self }
}

// MARK: - String

extension String: RawCodable {
    static func decode(from data: Data) throws(MapperError) -> String {
        guard let str = String(data: data, encoding: .utf8) else { throw .incorrect }
        return str
    }
    func encode() throws(MapperError) -> Data {
        guard let data = data(using: .utf8) else { throw .incorrect }
        return data
    }
}

// MARK: - Bool

extension Bool: RawDecodable {
    static func decode(from data: Data) throws(MapperError) -> Bool {
        guard let str = String(data: data, encoding: .utf8), let val = Bool(str) else { throw .incorrect }
        return val
    }
}

// MARK: - Int

extension Int: RawDecodable {
    static func decode(from data: Data) throws(MapperError) -> Int {
        guard let str = String(data: data, encoding: .utf8), let val = Int(str) else { throw .incorrect }
        return val
    }
}

// MARK: - Double

extension Double: RawDecodable {
    static func decode(from data: Data) throws(MapperError) -> Double {
        guard let str = String(data: data, encoding: .utf8), let val = Double(str) else { throw .incorrect }
        return val
    }
}

// MARK: - UIImage

#if canImport(UIKit)
extension UIImage: RawCodable {
    static func decode(from data: Data) throws(MapperError) -> Self {
        guard let image = Self(data: data) else { throw .incorrect }
        return image
    }
    func encode() throws(MapperError) -> Data {
        guard let data = pngData() else { throw .incorrect }
        return data
    }
}
#endif



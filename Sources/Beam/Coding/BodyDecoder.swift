//
//  BodyDecoder.swift
//  Beam
//
//  How a body becomes a value, chosen by the compiler from the value's type.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// How a body becomes a `Value`. `@API` and ``Endpoint`` pick one from the declared types;
/// build one only for a format of your own.
public struct BodyDecoder<Value>: Sendable {
    /// The `Accept` header to send, unless the route sets one.
    public let accept: ContentType?
    private let _decode: @Sendable (Data, JSONCoding) throws(CodingError) -> Value

    public init(
        accept: ContentType?,
        decode: @escaping @Sendable (Data, JSONCoding) throws(CodingError) -> Value
    ) {
        self.accept = accept
        self._decode = decode
    }

    /// Decodes `data`, using `json` when the body is JSON.
    public func decode(_ data: Data, with json: JSONCoding) throws(CodingError) -> Value {
        try _decode(data, json)
    }
}

// Decoding runs off the caller's actor: actor-isolated `Decodable` conformances need `nonisolated` DTOs.
extension BodyDecoder where Value: Decodable & SendableMetatype {
    /// JSON, decoded with the route's `JSONCoding`.
    public static var json: Self {
        Self(accept: .json) { (data, json) throws(CodingError) in try json.decode(Value.self, from: data) }
    }
}

extension BodyDecoder where Value == Data {
    /// The raw bytes.
    public static var data: Self {
        Self(accept: .data) { (data, _) throws(CodingError) in data }
    }
}

extension BodyDecoder where Value == String {
    /// The body as UTF-8 text.
    public static var text: Self {
        Self(accept: .text) { (data, _) throws(CodingError) in
            guard let text = String(data: data, encoding: .utf8) else { throw .typeMismatch }
            return text
        }
    }
}

extension BodyDecoder where Value == Void {
    /// No body: whatever arrives is ignored.
    public static var void: Self {
        Self(accept: nil) { (_, _) throws(CodingError) in () }
    }
}

extension BodyDecoder where Value: Decodable & SendableMetatype {
    /// Chosen by type as `@API` does: `String` is text, `Data` raw bytes, anything else JSON.
    public static var automatic: Self {
        if let text = BodyDecoder<String>.text as? Self { return text }
        if let data = BodyDecoder<Data>.data as? Self { return data }
        return .json
    }
}

// MARK: - BodyRepresentable

/// A non-`Decodable` body type that defines its own decoding. It can't also be `Decodable` (ambiguous).
public protocol BodyRepresentable: Sendable {
    /// The `Accept` header to send, unless the route sets one.
    static var bodyContentType: ContentType? { get }

    /// The value a body holds.
    static func decodeBody(_ data: Data) throws(CodingError) -> Self
}

extension BodyDecoder where Value: BodyRepresentable {
    /// The format the type itself defines.
    public static var representable: Self {
        Self(accept: Value.bodyContentType) { (data, _) throws(CodingError) in try Value.decodeBody(data) }
    }
}

#if canImport(UIKit)
extension UIImage: BodyRepresentable {
    public static var bodyContentType: ContentType? { .image }

    public static func decodeBody(_ data: Data) throws(CodingError) -> Self {
        guard let image = UIImage(data: data) as? Self else { throw .typeMismatch }
        return image
    }
}

extension BodyDecoder where Value == UIImage {
    /// An image, in any format `UIImage` reads.
    public static var image: Self { .representable }
}
#endif

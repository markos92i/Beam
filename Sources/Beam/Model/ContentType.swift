//
//  ContentType.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 10/3/25.
//

import Foundation
import UniformTypeIdentifiers

/// A `Content-Type` or `Accept` value, kept as written. Equal when they mean the same;
/// in a `switch`, matches by media type or family (`"image/*"`).
public struct ContentType: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The header value, as written.
    public let value: String

    public init(rawHeader: String) {
        value = rawHeader
    }

    public init(stringLiteral value: String) {
        self.value = value
    }

    /// The MIME type of `type`; `application/octet-stream` when it has none.
    public init(_ type: UTType) {
        value = type.preferredMIMEType ?? ContentType.data.value
    }

    /// From the file extension; `application/octet-stream` when it's unknown.
    public init(url: URL) {
        self.init(UTType(filenameExtension: url.pathExtension) ?? .data)
    }

    public var description: String { value }

    public var header: [String: String] { ["Content-Type": value] }

    /// The type without parameters, lowercased.
    public var mediaType: String {
        String(value.prefix { $0 != ";" }).trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The value of a parameter, whatever the case of its name.
    public func parameter(_ name: String) -> String? {
        parameters.first { $0.name == name.lowercased() }?.value
    }

    /// The uniform type of the media type, when the system knows it.
    public var utType: UTType? { UTType(mimeType: mediaType) }

    private var parameters: [(name: String, value: String)] {
        value.split(separator: ";").dropFirst().compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return nil }
            let value = parts[1].hasPrefix("\"") && parts[1].hasSuffix("\"") && parts[1].count > 1
                ? String(parts[1].dropFirst().dropLast()) : parts[1]
            return (parts[0].lowercased(), value)
        }
    }

    /// Only `charset` values are case-insensitive; a `boundary` is case-sensitive.
    private var normalized: String {
        let parameters = parameters
            .map { $0.name == "charset" ? ($0.name, $0.value.lowercased()) : $0 }
            .sorted { $0.name < $1.name }
            .map { "; \($0.name)=\($0.value)" }
        return mediaType + parameters.joined()
    }

    public static func == (lhs: ContentType, rhs: ContentType) -> Bool {
        lhs.normalized == rhs.normalized
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(normalized)
    }

    /// Matches by media type, or by family for `type/*` and `*/*`; parameters don't count.
    public static func ~= (pattern: ContentType, value: ContentType) -> Bool {
        let expected = pattern.mediaType
        if expected == "*/*" { return true }
        if expected.hasSuffix("/*") { return value.mediaType.hasPrefix(expected.dropLast()) }
        return value.mediaType == expected
    }
}

// MARK: - Common Types

extension ContentType {
    public static let json: ContentType = "application/json; charset=UTF-8"
    public static let text: ContentType = "text/plain; charset=UTF-8"
    public static let xml: ContentType = "application/xml; charset=UTF-8"
    public static let html: ContentType = "text/html"
    public static let pdf: ContentType = "application/pdf"
    public static let data: ContentType = "application/octet-stream"
    public static let urlEncoded: ContentType = "application/x-www-form-urlencoded"

    public static func multipart(boundary: String) -> ContentType {
        ContentType(rawHeader: "multipart/form-data; boundary=\(boundary)")
    }

    public static let png = ContentType(.png)
    public static let jpeg = ContentType(.jpeg)
    public static let heic = ContentType(.heic)
    public static let gif = ContentType(.gif)
    public static let webp = ContentType(.webP)
    public static let svg = ContentType(.svg)
    public static let mp4 = ContentType(.mpeg4Movie)
    public static let mov = ContentType(.quickTimeMovie)
    public static let mp3 = ContentType(.mp3)
    public static let m4a = ContentType(.mpeg4Audio)
    public static let wav = ContentType(.wav)
    public static let csv = ContentType(.commaSeparatedText)

    /// Any image (`image/*`), for an `Accept` or a `switch` case.
    public static let image: ContentType = "image/*"
    public static let video: ContentType = "video/*"
    public static let audio: ContentType = "audio/*"
}

// MARK: - Internal

extension ContentType {
    var isText: Bool {
        let type = mediaType
        return type.hasPrefix("text/") || type.contains("json") || type.contains("xml") || self ~= .urlEncoded
    }
}

extension HTTPURLResponse {
    var contentType: ContentType? {
        (value(forHTTPHeaderField: "Content-Type") ?? mimeType).map(ContentType.init(rawHeader:))
    }
}

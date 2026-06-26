//
//  ContentType.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 10/3/25.
//

import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

public enum ContentType: Sendable, Equatable {
    case urlEncoded
    case data
    case pdf
    case html
    case json(charset: Charset = .utf8)
    case text(charset: Charset = .utf8)
    case xml(charset: Charset = .utf8)
    case multipart(boundary: String)
    case image(format: ImageFormat)
    case video(format: VideoFormat)
    case audio(format: AudioFormat)
    case custom(String)
    
    public enum Charset: Sendable, Equatable {
        case utf8
        case utf16
        case ascii
        case iso8859_1
        case custom(String)
        
        public var value: String {
            switch self {
            case .utf8: "UTF-8"
            case .utf16: "UTF-16"
            case .ascii: "US-ASCII"
            case .iso8859_1: "ISO-8859-1"
            case .custom(let value): value
            }
        }
    }
    
    public enum ImageFormat: String, Sendable {
        case avif
        case apng
        case gif
        case heic
        case heif
        case jpeg
        case png
        case svg
        case webp
    }

    public enum VideoFormat: String, Sendable {
        case mp4
        case mov
        case avi
        case webm
        case mpeg
    }

    public enum AudioFormat: String, Sendable {
        case mp3
        case aac
        case wav
        case ogg
        case m4a
    }
}

// MARK: - Type Inference

extension ContentType {
    /// Infers the appropriate Accept content type for a given Swift response type.
    /// Returns `nil` when no Accept header should be sent (e.g., `Void`).
    public static func inferred<T>(for type: T.Type) -> ContentType? {
        switch type {
        case is Data.Type: .data
        case is String.Type, is Bool.Type: .text()
        case is Void.Type: nil
        #if canImport(UIKit)
        case is UIImage.Type: .custom("image/*")
        #endif
        case is Codable.Type: .json()
        default: nil
        }
    }
}

// MARK: - MIME Value

extension ContentType {
    public var value: String {
        switch self {
        case .urlEncoded: "application/x-www-form-urlencoded"
        case .data: "application/octet-stream"
        case .pdf: "application/pdf"
        case .json(let charset): "application/json; charset=\(charset.value)"
        case .text(let charset): "text/plain; charset=\(charset.value)"
        case .xml(let charset): "application/xml; charset=\(charset.value)"
        case .html: "text/html"
        case .multipart(let boundary): "multipart/form-data; boundary=\(boundary)"
        case .image(let format): "image/\(format.rawValue)"
        case .video(let format): "video/\(format.rawValue)"
        case .audio(let format): "audio/\(format.rawValue)"
        case .custom(let customValue): customValue
        }
    }
    
    public var header: [String: String] { ["Content-Type": value] }
}

extension ContentType {
    public var icon: String {
        switch self {
        case .json: "􀡅"
        case .image: "􀏅"
        case .video: "􀜤"
        case .audio: "􀑪"
        case .multipart: "􀏭"
        case .data: "􀤧"
        case .text: "􀅒"
        case .xml: "􀙚"
        case .html: "􀙚"
        case .pdf: "􀈷"
        case .urlEncoded: "􀒶"
        case .custom: "􀠩"
        }
    }

    public var label: String {
        switch self {
        case .json: "json"
        case .image(let f): "image/\(f.rawValue)"
        case .video(let f): "video/\(f.rawValue)"
        case .audio(let f): "audio/\(f.rawValue)"
        case .multipart: "multipart"
        case .data: "stream"
        case .text: "text"
        case .xml: "xml"
        case .html: "html"
        case .pdf: "pdf"
        case .urlEncoded: "form"
        case .custom(let v): v
        }
    }

    public init(rawHeader: String) {
        let lower = rawHeader.lowercased()
        let mimeType = lower.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? lower

        switch mimeType {
        case "application/json": self = .json()
        case "text/html": self = .html
        case "text/plain": self = .text()
        case "application/xml", "text/xml": self = .xml()
        case "application/pdf": self = .pdf
        case "application/octet-stream": self = .data
        case "application/x-www-form-urlencoded": self = .urlEncoded
        default:
            if mimeType.hasPrefix("image/") {
                let format = String(mimeType.dropFirst("image/".count))
                self = .image(format: ImageFormat(rawValue: format) ?? .jpeg)
            } else if mimeType.hasPrefix("video/") {
                let format = String(mimeType.dropFirst("video/".count))
                self = .video(format: VideoFormat(rawValue: format) ?? .mp4)
            } else if mimeType.hasPrefix("audio/") {
                let format = String(mimeType.dropFirst("audio/".count))
                self = .audio(format: AudioFormat(rawValue: format) ?? .mp3)
            } else if mimeType.hasPrefix("multipart/") {
                let boundary = rawHeader.split(separator: ";")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { $0.lowercased().hasPrefix("boundary=") }
                    .map { String($0.dropFirst("boundary=".count)) } ?? ""
                self = .multipart(boundary: boundary)
            } else {
                self = .custom(rawHeader)
            }
        }
    }
}

// MARK: - File URL Inference

extension ContentType {
    /// Infers the content type from a file URL using UTType.
    /// Falls back to `.data` (application/octet-stream) if the type cannot be determined.
    ///
    /// Useful for uploads where the content type should match the file:
    /// ```swift
    /// let body: HTTPBody = .data(fileData, contentType: ContentType(url: videoURL))
    /// ```
    public init(url: URL) {
        let utType = UTType(filenameExtension: url.pathExtension)
        let mime = utType?.preferredMIMEType ?? "application/octet-stream"
        self = ContentType(rawHeader: mime)
    }
}

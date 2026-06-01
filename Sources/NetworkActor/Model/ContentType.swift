//
//  ContentType.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 10/3/25.
//

import Foundation

public enum ContentType: Sendable {
    case urlEncoded
    case data
    case pdf
    case json(charset: Charset = .utf8)
    case text(charset: Charset = .utf8)
    case xml(charset: Charset = .utf8)
    case multipart(boundary: String)
    case image(format: ImageFormat)
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
}

extension ContentType {
    public var value: String {
        switch self {
        case .urlEncoded: "application/x-www-form-urlencoded"
        case .data: "application/octet-stream"
        case .pdf: "application/pdf"
        case .json(let charset): "application/json; charset=\(charset.value)"
        case .text(let charset): "text/plain; charset=\(charset.value)"
        case .xml(let charset): "application/xml; charset=\(charset.value)"
        case .multipart(let boundary): "multipart/form-data; boundary=\(boundary)"
        case .image(let format): "image/\(format.rawValue)"
        case .custom(let customValue): customValue
        }
    }
    
    public var header: [String: String] { ["Content-Type": value] }
}

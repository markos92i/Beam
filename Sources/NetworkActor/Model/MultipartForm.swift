//
//  MultipartForm.swift
//  Project Dark
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation
import UniformTypeIdentifiers

/// A model representing multipart form data configuration.
public struct MultipartForm: Sendable {
    /// Boundary string used to separate parts.
    let boundary: String = "Boundary-\(UUID().uuidString)"
    
    /// Data of the file/s to upload.
    private let media: [Media]
    
    /// Parameters to include in the multipart form data.
    private let parameters: [String: String]

    public init(parameters: [String: String] = [:], media: [Media]) {
        self.parameters = parameters
        self.media = media
    }
}

extension MultipartForm {
    public var header: [String: String] { ContentType.multipart(boundary: boundary).header }
    public var body: Data? {
        get throws {
            var body = Data()
            
            // Text parameters
            for (key, value) in parameters {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }
            
            // Multimedia files
            for file in media {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(file.key)\"; filename=\"\(file.fileName)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: \(file.mimeType)\r\n\r\n".data(using: .utf8)!)
                body.append(try file.data)
                body.append("\r\n".data(using: .utf8)!)
            }
            
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            return body
        }
    }
}

public struct Media: Sendable {
    let url: URL
    let key: String

    var fileName: String { url.lastPathComponent }
    var mimeType: String { UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream" }

    public init(url: URL, key: String) {
        self.url = url
        self.key = key
    }
}

extension Media {
    var data: Data { get throws { try Data(contentsOf: url) } }
}

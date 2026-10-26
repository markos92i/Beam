//
//  MultipartForm.swift
//  Project Dark
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation

/// A multipart form: text parameters and files.
public struct MultipartForm: Sendable {
    let boundary: String = "Boundary-\(UUID().uuidString)"
    
    private let media: [Media]
    
    private let parameters: [String: String]

    public init(parameters: [String: String] = [:], media: [Media]) {
        self.parameters = parameters
        self.media = media
    }
}

extension MultipartForm {
    public var header: [String: String] { ContentType.multipart(boundary: boundary).header }
    public var body: Data {
        get throws(FileError) {
            var body = Data()

            for (key, value) in parameters {
                body.append(Data("--\(boundary)\r\n".utf8))
                body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
                body.append(Data("\(value)\r\n".utf8))
            }

            for file in media {
                body.append(Data("--\(boundary)\r\n".utf8))
                body.append(Data("Content-Disposition: form-data; name=\"\(file.key)\"; filename=\"\(file.fileName)\"\r\n".utf8))
                body.append(Data("Content-Type: \(file.mimeType)\r\n\r\n".utf8))
                body.append(try file.data)
                body.append(Data("\r\n".utf8))
            }

            body.append(Data("--\(boundary)--\r\n".utf8))
            return body
        }
    }
}

public struct Media: Sendable {
    let url: URL
    let key: String

    var fileName: String { url.lastPathComponent }
    var mimeType: String { ContentType(url: url).value }

    public init(url: URL, key: String) {
        self.url = url
        self.key = key
    }
}

extension Media {
    var data: Data { get throws(FileError) { try FileUtils.read(url) } }
}

//
//  APIRequest.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 13/3/25.
//

import Foundation

public struct APIRequest: Sendable {
    public var method: HTTPMethod
    public var host: String
    public var path: String
    public var pathTemplate: String
    public var query: [URLQueryItem] = []
    public var headers: [String: String] = [:]
    public var accept: ContentType? = nil
    public var body: HTTPBody? = nil
    
    public init(
        method: HTTPMethod,
        host: String,
        path: String,
        pathTemplate: String = "",
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        accept: ContentType? = nil,
        body: HTTPBody? = nil
    ) {
        self.method = method
        self.host = host
        self.path = path
        self.pathTemplate = pathTemplate
        self.query = query
        self.headers = headers
        self.accept = accept
        self.body = body
    }
}

extension APIRequest {
    public var url: URL? {
        guard var urlComponents = URLComponents(string: host) else { return nil }

        // Append path (preserving any existing path in host)
        let basePath = urlComponents.path
        let fullPath = basePath.isEmpty || basePath == "/"
            ? path
            : basePath + path
        urlComponents.path = fullPath

        // Merge query items
        let allItems = (urlComponents.queryItems ?? []) + query
        urlComponents.queryItems = allItems.isEmpty ? nil : allItems

        return urlComponents.url
    }

    /// Auto-generated headers from body content type.
    public var contentHeaders: [String: String] { body?.contentType.header ?? [:] }

    /// Merges all headers: auto-generated first, then user-defined (user wins on conflict).
    public var allHeaders: [String: String] { contentHeaders.merging(headers) { _, user in user } }
}

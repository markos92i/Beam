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
    /// The route with `{name}` placeholders: groups error reports and identifies background transfers.
    public var pathTemplate: String
    public var query: [URLQueryItem] = []
    public var headers: [String: String] = [:]
    public var body: HTTPBody? = nil

    /// Set by `@API` so a placeholder value containing `/` stays inside its segment.
    var percentEncodedPath: String? = nil

    /// The ``APIValues`` property the route found `nil`; fails the request before sending.
    var missingValue: String? = nil
    
    public init(
        method: HTTPMethod,
        host: String,
        path: String,
        pathTemplate: String? = nil,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: HTTPBody? = nil
    ) {
        self.method = method
        self.host = host
        self.path = path
        self.pathTemplate = pathTemplate ?? path
        self.query = query
        self.headers = headers
        self.body = body
    }
}

extension APIRequest {
    public var url: URL? {
        guard var urlComponents = URLComponents(string: host) else { return nil }

        if let percentEncodedPath {
            let basePath = urlComponents.percentEncodedPath
            urlComponents.percentEncodedPath = basePath.isEmpty || basePath == "/"
                ? percentEncodedPath
                : basePath + percentEncodedPath
        } else {
            let basePath = urlComponents.path
            urlComponents.path = basePath.isEmpty || basePath == "/"
                ? path
                : basePath + path
        }

        let allItems = (urlComponents.queryItems ?? []) + query
        urlComponents.queryItems = allItems.isEmpty ? nil : allItems

        return urlComponents.url
    }

    /// Headers derived from the body's content type.
    public var contentHeaders: [String: String] { body?.contentType.header ?? [:] }

    /// ``contentHeaders`` merged with ``headers``, which win on conflict.
    public var allHeaders: [String: String] { contentHeaders.merging(headers) { _, user in user } }
}

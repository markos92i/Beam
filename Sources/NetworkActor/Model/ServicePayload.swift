//
//  ServicePayload.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 13/3/25.
//

import Foundation

public struct ServicePayload: Sendable {
    public var method: HTTPMethod
    public var host: String
    public var path: String
    public var params: [URLQueryItem] = []
    public var headers: [String : String] = [:]
    public var body: HTTPBody? = nil
    public var timeout: TimeInterval = 60
    
    public init(
        method: HTTPMethod,
        host: String,
        path: String,
        params: [URLQueryItem] = [],
        headers: [String : String] = [:],
        body: HTTPBody? = nil,
        timeout: TimeInterval = 60
    ) {
        self.method = method
        self.host = host
        self.path = path
        self.params = params
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

extension ServicePayload {
    public var url: URL? {
        guard let base = URL(string: host), var urlComponents = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: true) else { return nil }
        
        if urlComponents.queryItems != nil {
            urlComponents.queryItems?.append(contentsOf: params)
        } else {
            urlComponents.queryItems = params
        }
        
        return urlComponents.url
    }
    
    public var contentHeaders: [String : String] {
        switch body {
        case .data: [:]
        case .dictionary: ContentType.json().header
        case .json: ContentType.json().header
        case .multipart(let multipart): multipart.header
        case .none: [:]
        }
    }
    
    public var allHeaders: [String : String] { headers.merging(contentHeaders) { $1 } }
    
    public func data(with serializer: SerializerProtocol) throws -> Data? { try body?.data(with: serializer) }
}

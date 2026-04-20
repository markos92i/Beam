//
//  ServicePayload.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation

public struct ServicePayload: Sendable {
    public var method: HTTPMethod
    public var baseURL: String
    public var path: String
    public var params: [URLQueryItem] = []
    public var headers: [String : String] = [:]
    public var body: Sendable? = nil
    public var data: Data? = nil
    public var timeout: TimeInterval = 60
    
    public init(
        method: HTTPMethod,
        baseURL: String,
        path: String,
        params: [URLQueryItem] = [],
        headers: [String : String] = [:],
        body: Sendable? = nil,
        data: Data? = nil,
        timeout: TimeInterval = 60
    ) {
        self.method = method
        self.baseURL = baseURL
        self.path = path
        self.params = params
        self.headers = headers
        self.body = body
        self.data = data
        self.timeout = timeout
    }
}

extension ServicePayload {
    public var url: URL? {
        var urlComponents = URLComponents(string: baseURL + path)
        if urlComponents?.queryItems != nil {
            urlComponents?.queryItems?.append(contentsOf: params)
        } else {
            urlComponents?.queryItems = params
        }
        return urlComponents?.url
    }
}

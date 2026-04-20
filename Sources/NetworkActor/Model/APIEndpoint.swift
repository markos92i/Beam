//
//  APIEndpoint.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation

public struct APIEndpoint: APIEndpointProtocol {
    public var method: HTTPMethod
    public var baseURL: String
    public var path: String
    public var params: [URLQueryItem] = []
    public var headers: [String : String] = [:]
    public var body: Data? = nil
    public var data: Data? = nil
    public var timeout: TimeInterval = 30
}

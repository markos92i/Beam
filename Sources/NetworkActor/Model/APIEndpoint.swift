//
//  APIEndpoint.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
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

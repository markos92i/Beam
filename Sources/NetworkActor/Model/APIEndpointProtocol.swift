//
//  APIEndpointProtocol.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation

public protocol APIEndpointProtocol: Sendable {
    /// HTTP method used by the endpoint.
    var method: HTTPMethod { get }
    
    /// Base URL for the API.
    var baseURL: String { get }

    /// Path for the endpoint.
    var path: String { get }
            
    /// URL parameters for the request.
    var params: [URLQueryItem] { get }
    
    /// Headers for the request.
    var headers: [String: String] { get }

    /// Body data for the request.
    var body: Data? { get }
    
    /// Bare data for the upload.
    var data: Data? { get }
        
    /// Timeout time for call
    var timeout: TimeInterval { get }
    
    /// URLRequest representation of the endpoint.
    var urlRequest: URLRequest? { get }
}

extension APIEndpointProtocol {
    public var urlRequest: URLRequest? {
        var urlComponents = URLComponents(string: baseURL + path)
        if urlComponents?.queryItems != nil {
            urlComponents?.queryItems?.append(contentsOf: params)
        } else {
            urlComponents?.queryItems = params
        }


        guard let url = urlComponents?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        request.timeoutInterval = timeout
        
        return request
    }
}

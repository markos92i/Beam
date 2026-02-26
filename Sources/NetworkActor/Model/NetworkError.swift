//
//  NetworkError.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import Foundation

public struct NetworkError: Error {
    var type: NetworkErrorType
    var body: Data?
    
    public init(type: NetworkErrorType, body: Data? = nil) {
        self.type = type
        self.body = body
    }
}

extension NetworkError: CustomNSError {
    public static var errorDomain: String { Bundle.main.bundleIdentifier ?? "es.randstad.candidate" }
    
    public var errorCode: Int { type.rawValue }
    
    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = type.errorUserInfo
        
        if let body, let bodyString = String(data: body, encoding: .utf8) {
            userInfo["response_body"] = bodyString
        }
        
        return userInfo
    }
}

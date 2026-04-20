//
//  NetworkError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
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
            userInfo["ResponseBody"] = bodyString
        }
        
        return userInfo
    }
}

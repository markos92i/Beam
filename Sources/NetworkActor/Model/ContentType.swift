//
//  ContentType.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 10/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import Foundation

public enum ContentType {
    case urlEncoded
    case data
    case json
    case multipart(String)
}

extension ContentType {
    public var value: String {
        switch self {
        case .urlEncoded: "application/x-www-form-urlencoded"
        case .data: "application/octet-stream"
        case .json: "application/json; charset=UTF-8"
        case .multipart(let boundary): "multipart/form-data; boundary=\(boundary)"
        }
    }
    
    public var header: [String : String] { ["Content-Type": value] }
}

//
//  ContentType.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
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

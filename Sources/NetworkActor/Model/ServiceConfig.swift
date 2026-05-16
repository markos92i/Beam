//
//  ServiceConfig.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 14/05/2026.
//

import Foundation

public struct ServiceConfig: Sendable {
    public var maxRetries: Int
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder
    
    public static let defaultEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    public static let defaultDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    public init(
        maxRetries: Int = 1,
        encoder: JSONEncoder = defaultEncoder,
        decoder: JSONDecoder = defaultDecoder
    ) {
        self.maxRetries = maxRetries
        self.encoder = encoder
        self.decoder = decoder
    }
    
    public static let standard = ServiceConfig()
}

//
//  ServiceConfig.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 14/05/2026.
//

import Foundation

public struct ServiceConfig: Sendable {
    public var maxRetries: Int
    
    public init(
        maxRetries: Int = 1,
    ) {
        self.maxRetries = maxRetries
    }
    
    public static let standard = ServiceConfig()
}

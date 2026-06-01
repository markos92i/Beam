//
//  ServiceConfig.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 14/05/2026.
//

import Foundation

public struct ServiceConfig: Sendable {
    public var maxRetries: Int
    public var localCacheFile: String? = nil

    public init(
        maxRetries: Int = 1,
        localCacheFile: String? = nil,
    ) {
        self.maxRetries = maxRetries
        self.localCacheFile = localCacheFile
    }
    
    public static let standard = ServiceConfig()
}

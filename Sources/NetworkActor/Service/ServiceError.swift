//
//  ServiceError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation

public struct ServiceError<Value: Sendable>: Error, Equatable {
    public var type: ServiceErrorType
    public var body: Value?
    
    public init(type: ServiceErrorType, body: Value? = nil) {
        self.type = type
        self.body = body
    }
    
    public static func == (lhs: ServiceError<Value>, rhs: ServiceError<Value>) -> Bool {
        lhs.type == rhs.type
    }
}

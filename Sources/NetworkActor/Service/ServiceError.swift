//
//  ServiceError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//


import Foundation

public struct ServiceError<Value: Sendable>: Error, Equatable {
    public var type: NetworkErrorType
    public var body: Value?
    
    public init(type: NetworkErrorType, body: Value? = nil) {
        self.type = type
        self.body = body
    }
    
    public static func == (lhs: ServiceError<Value>, rhs: ServiceError<Value>) -> Bool {
        lhs.type == rhs.type
    }
}

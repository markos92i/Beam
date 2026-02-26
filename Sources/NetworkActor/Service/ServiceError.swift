//
//  ServiceError.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
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

//
//  Token.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation

public struct Token: Sendable {
    public var id: String
    public var date: Date
    public var expiration: TimeInterval
    
    public init(
        id: String,
        date: Date,
        expiration: TimeInterval
    ) {
        self.id = id
        self.date = date
        self.expiration = expiration
    }
}

extension Token {
    public var isValid: Bool { Date.now < date.addingTimeInterval(expiration) }
}

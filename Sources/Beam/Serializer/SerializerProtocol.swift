//
//  SerializerProtocol.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 01/06/2026.
//

import Foundation

public protocol SerializerProtocol: Sendable {
    func encode<Value>(_ value: Value) throws -> Data
    func decode<Value>(data: Data) throws -> Value
}

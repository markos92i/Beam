//
//  MapperProtocol.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 01/06/2026.
//

import Foundation

public protocol MapperProtocol: Sendable {
    func encode(_ value: some Encodable) throws(MapperError) -> Data
    func decode<Value>(data: Data) throws(MapperError) -> Value
}

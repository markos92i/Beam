//
//  CrashProtocol.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 30/3/25.
//

import Foundation

public protocol CrashProtocol: Sendable {
    func report(error: Error, info: [String: Any])
    func log(_ output: String)
}

extension CrashProtocol {
    public func log(_ output: String) {}
}

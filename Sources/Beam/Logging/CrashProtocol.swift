//
//  CrashProtocol.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 30/3/25.
//

import Foundation

public protocol CrashProtocol: Sendable {
    func report(error: Error, info: [String: String])
}

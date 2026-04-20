//
//  CrashProtocol.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation

public protocol CrashProtocol: Sendable {
    func report(error: Error, userInfo: [String: Any])
}

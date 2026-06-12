//
//  InfoError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/06/2026.
//

import Foundation

protocol InfoError: Error {
    var info: [String: any Sendable] { get }
}

//
//  HTTPBody.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 18/05/2026.
//

import Foundation

public enum HTTPBody: Sendable {
    case json(Sendable)
    case data(Data)
    case multipart(MultipartForm)
    case empty
}

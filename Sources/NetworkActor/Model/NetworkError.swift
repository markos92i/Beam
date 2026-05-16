//
//  NetworkError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

public enum NetworkError: Error {
    case invalidURL
    case noResponse
    case fileError(FileError)
    case url(URLError)
    case http(code: Int, data: Data?)
    case unknown(Error)
    
    public init(fileError: FileError) {
        self = .fileError(fileError)
    }
    
    var description: String? {
        switch self {
        case .invalidURL: "La URL no es válida"
        case .noResponse: "No se recibió respuesta del servidor"
        case .fileError(let error): "Error al guardar archivo: \(error.localizedDescription)"
        case .url(let error): error.localizedDescription
        case .http(let code, _): HTTPStatus(rawValue: code)?.description
        case .unknown(let error): error.localizedDescription
        }
    }

    var statusCode: Int {
        if case .http(let code, _) = self { code } else { -1000 }
    }

    var isRetryable: Bool {
        switch self {
        case .url(let error):
            return error.code == .timedOut || error.code == .networkConnectionLost
        case .http(let code, _):
            return code >= 500 || code == 429
        default:
            return false
        }
    }
}

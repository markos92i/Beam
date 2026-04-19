//
//  NetworkErrorType.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 10/2/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import Foundation

public enum NetworkErrorType: Int, Error, Identifiable, CustomStringConvertible {
    case encode = 0
    case decode = 1
    case storage = 2
    case invalidURL = 3
    case invalidFormat = 4
    case noResponse = 5
    
    case canceled = 8
    case timedOut = 9
    case noConnection = 10
    case serverUnreachable = 11
    case sslError = 12
    case unknown = 99

    case badRequest = 400
    case unauthorized = 401
    case forbidden = 403
    case notFound = 404
    case conflict = 409
    case serverError = 500
    
    case unexpectedCode = 1000

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .encode:           "Petición incorrecta"
        case .decode:           "Respuesta incorrecta"
        case .storage:          "Error de almacenamiento"
        case .invalidURL:       "URL incorrecta"
        case .invalidFormat:    "Formato incorrecto"
        case .noResponse:       "Sin respuesta"

        case .canceled:         "Operación cancelada"
        case .timedOut:         "Demasiado tiempo sin respuesta"
        case .noConnection:     "Sin internet"
        case .serverUnreachable:"Servidor no alcanzable"
        case .sslError:         "Fallo SSL"
        case .unknown:          "Error desconocido"
            
        case .badRequest:       "Petición incorrecta"
        case .unauthorized:     "Sesión expirada"
        case .forbidden:        "Acceso prohibido"
        case .notFound:         "Recurso no encontrado"
        case .conflict:         "Conflicto"
        case .serverError:      "Fallo en el servidor"
            
        case .unexpectedCode:   "Error inesperado"
        }
    }

    public var description: String {
        switch self {
        case .encode:           "El contenido de la peticíon no es correcto"
        case .decode:           "El contenido de la respuesta no es correcto"
        case .storage:          "El contenido descargado no se ha podido guardar en el almacenamiento"
        case .invalidURL:       "La dirección es incorrecta"
        case .invalidFormat:    "El contenido de respuesta tiene un formato incorrecto"
        case .noResponse:       "No se ha recibido ninguna respuesta"
            
        case .canceled:         "La operación se ha cancelado antes de terminar"
        case .timedOut:         "Se ha superado el tiempo limite de espera sin obtener respuesta"
        case .noConnection:     "No hay conexión a internet, comprueba la red wifi o telefónica"
        case .serverUnreachable:"No se ha podido llegar al servidor, algun punto intermedio ha fallado"
        case .sslError:         "No se ha podido establecer una comunicación segura mediante SSL"
        case .unknown:          "Ha ocurrido un error desconocido"

        case .badRequest:       "Petición incorrecta o mal formada"
        case .unauthorized:     "No tienes autorización para realizar esta operación"
        case .forbidden:        "No tienes los permisos necesarios para realizar esta operación"
        case .notFound:         "No se ha encontrado el recurso en la url especificada"
        case .conflict:         "No se ha podido completar la operación debido a un conflicto"
        case .serverError:      "El servidor ha tenido un fallo interno"
            
        case .unexpectedCode:   "Ha ocurrido un error inesperado"
        }
    }
}

extension NetworkErrorType: CustomNSError {
    public static var errorDomain: String { Bundle.main.bundleIdentifier ?? "es.randstad.candidate" }
    
    public var errorCode: Int { rawValue }
    
    public var errorUserInfo: [String: Any] {
        [
            NSLocalizedDescriptionKey: "\(rawValue): \(title)",
            NSLocalizedFailureReasonErrorKey: description
        ]
    }
}

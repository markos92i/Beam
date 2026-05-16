//
//  ServiceError.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation

public enum ServiceError<Failure: Sendable>: Error, Identifiable, CustomStringConvertible {
    case encode
    case decode
    case storage
    case invalidURL
    case invalidFormat
    case noResponse
    
    case cancelled
    case timedOut
    case noConnection
    case serverUnreachable
    case sslError
    case unknown

    // Errores HTTP con valor asociado genérico (el Dto de error del backend)
    case badRequest(Failure?)
    case unauthorized(Failure?)
    case forbidden(Failure?)
    case notFound(Failure?)
    case conflict(Failure?)
    case serverError(Failure?)
    
    case unexpectedCode(statusCode: Int, body: Failure?)

    // MARK: - Identifiable Compliance
    public var id: Int {
        switch self {
        case .encode: 0
        case .decode: 1
        case .storage: 2
        case .invalidURL: 3
        case .invalidFormat: 4
        case .noResponse: 5
        
        case .cancelled: 8
        case .timedOut: 9
        case .noConnection: 10
        case .serverUnreachable: 11
        case .sslError: 12
        case .unknown: 99

        case .badRequest: 400
        case .unauthorized: 401
        case .forbidden: 403
        case .notFound: 404
        case .conflict: 409
        case .serverError: 500
            
        case .unexpectedCode(let statusCode, _): statusCode
        }
    }

    public var title: String {
        switch self {
        case .encode:           "Petición incorrecta"
        case .decode:           "Respuesta incorrecta"
        case .storage:          "Error de almacenamiento"
        case .invalidURL:       "URL incorrecta"
        case .invalidFormat:    "Formato incorrecto"
        case .noResponse:       "Sin respuesta"

        case .cancelled:         "Operación cancelada"
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
            
        case .cancelled:         "La operación se ha cancelado antes de terminar"
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

extension ServiceError {
    init(from networkError: NetworkError, serializer: Serializer) {
        switch networkError {
        case .http(let statusCode, let data):
            let decodedBody: Failure? = data.flatMap { try? serializer.decode(data: $0) }
            switch statusCode {
            case 400: self = .badRequest(decodedBody)
            case 401: self = .unauthorized(decodedBody)
            case 403: self = .forbidden(decodedBody)
            case 404: self = .notFound(decodedBody)
            case 409: self = .conflict(decodedBody)
            case 500...599: self = .serverError(decodedBody)
            default: self = .unexpectedCode(statusCode: statusCode, body: decodedBody)
            }
        case .url(let urlError):
            switch urlError.code {
            case .timedOut: self = .timedOut
            case .cancelled: self = .cancelled
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: self = .noConnection
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted: self = .sslError
            case .cannotFindHost, .dnsLookupFailed: self = .serverUnreachable
            default: self = .unknown
            }
        case .noResponse: self = .noResponse
        case .invalidURL: self = .invalidURL
        default: self = .unknown
        }
    }
    
    init(from authError: AuthError) {
        switch authError {
        case .missingToken, .invalidCredentials, .failedToRefreshToken:
            self = .unauthorized(nil)
        case .unknown:
            self = .unknown
        }
    }
    
    init(from fileError: FileError) {
        switch fileError {
        case .invalidTargetURL, .removeFailed, .copyFailed:
            self = .storage
        }
    }
    
    init(from serializerError: SerializerError) {
        switch serializerError {
        case .encoding: self = .encode
        case .decoding: self = .decode
        }
        
    }
}

// MARK: - Equatable Compliance
extension ServiceError: Equatable {
    public static func == (lhs: ServiceError<Failure>, rhs: ServiceError<Failure>) -> Bool {
        lhs.id == rhs.id
    }
}

extension ServiceError: CustomNSError {
    public static var errorDomain: String { Bundle.main.bundleIdentifier ?? "network.actor" }
    
    public var errorCode: Int { id }
    
    public var errorUserInfo: [String: Any] {
        [
            NSLocalizedDescriptionKey: "\(id): \(title)",
            NSLocalizedFailureReasonErrorKey: description
        ]
    }
}

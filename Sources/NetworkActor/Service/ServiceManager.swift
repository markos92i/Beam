//
//  ServiceManager.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import SwiftUI

public struct ServiceManager<Success: Sendable, Failure: Sendable>: Sendable {
    public var network: NetworkActor
    public var auth: (any AuthProtocol)? = nil
    public var crash: CrashProtocol? = nil
    public var api: ServicePayload
    public var config: ServiceConfig
    
    private let serializer: Serializer
    
    public init(
        network: NetworkActor,
        auth: (any AuthProtocol)? = nil,
        crash: CrashProtocol? = nil,
        api: ServicePayload,
        config: ServiceConfig = .standard
    ) {
        self.network = network
        self.auth = auth
        self.crash = crash
        self.api = api
        self.config = config
        
        self.serializer = Serializer(encoder: config.encoder, decoder: config.decoder)
    }
    
    // MARK: - Throwing Core Implementation
    @concurrent private func performOperation(operation: (APIEndpoint) async throws -> Success) async throws(ServiceError<Failure>) -> Success {
        for attempt in 0...config.maxRetries {
            do {
                let api = try await prepare(payload: self.api)
                
                return try await operation(api)
            } catch let error as AuthError {
                guard !(attempt == config.maxRetries), let auth else {
                    throw mapError(error)
                }
                
                await auth.invalidate()
            } catch {
                throw mapError(error)
            }
        }
        
        throw ServiceError<Failure>(type: .unknown)
    }
    
    @concurrent public func request() async throws(ServiceError<Failure>) -> Success {
        try await performOperation() { api in
            let data: Data = try await network.request(api: api)
            guard let decoded: Success = try serializer.decode(data: data) else {
                throw ServiceError<Failure>(type: .decode)
            }
            return decoded
        }
    }
    
    @concurrent public func upload() async throws(ServiceError<Failure>) -> Success {
        try await performOperation() { api in
            let data: Data = try await network.upload(api: api, data: api.data ?? Data())
            guard let decoded: Success = try serializer.decode(data: data) else {
                throw ServiceError<Failure>(type: .decode)
            }
            return decoded
        }
    }
    
    @concurrent public func file(file: String) async throws(ServiceError<Failure>) -> Success {
        do {
            guard let url = Bundle.main.url(forResource: file, withExtension: nil) else {
                throw ServiceError<Failure>(type: .invalidURL)
            }
            let data = try Data(contentsOf: url)
            guard let decoded: Success = try serializer.decode(data: data) else {
                throw ServiceError<Failure>(type: .decode)
            }
            return decoded
        } catch {
            throw mapError(error)
        }
    }
    
    // MARK: - Private Helpers
    @concurrent private func prepare(payload: ServicePayload) async throws -> APIEndpoint {
        var api = APIEndpoint(
            method: payload.method,
            baseURL: payload.baseURL,
            path: payload.path,
            params: payload.params,
            headers: payload.headers,
            body: try serializer.encode(payload.body),
            data: payload.data,
            timeout: payload.timeout
        )
        
        if let auth {
            api.headers.merge(try await auth.authHeader) { $1 }
        }
        
        return api
    }
    
    @concurrent public func cancel() async {
        await network.cancel()
    }
}

extension ServiceManager where Success == URL {
    @concurrent public func download() async throws(ServiceError<Failure>) -> URL {
        try await performOperation() { api in
            try await network.download(api: api)
        }
    }
}

// MARK: Error management and reporting
extension ServiceManager {
    private func mapError(_ error: Error) -> ServiceError<Failure> {
        if let serviceError = error as? ServiceError<Failure> { return serviceError }
        
        var finalServiceError: ServiceError<Failure>
        var extraInfo: [String: Any] = [:]
        
        switch error {
        case is AuthError:
            finalServiceError = ServiceError<Failure>(type: .unauthorized)
        case let fileError as FileError:
            switch fileError {
            case .invalidTargetURL:
                finalServiceError = ServiceError<Failure>(type: .storage)
            case .removeFailed(let error):
                finalServiceError = ServiceError<Failure>(type: .storage)
            case .copyFailed(let error):
                finalServiceError = ServiceError<Failure>(type: .storage)
            }

        case let serializerError as SerializerError:
            switch serializerError {
            case .encoding(_, let info):
                finalServiceError = ServiceError<Failure>(type: .encode)
                extraInfo = info
            case .decoding(_, let info):
                finalServiceError = ServiceError<Failure>(type: .decode)
                extraInfo = info
            }
            
        case let networkError as NetworkError:
            // Intentamos decodificar los bytes del body de red al Dto genérico 'Failure' que espera la App
            var decodedErrorBody: Failure? = nil
            if let bodyData = networkError.body {
                decodedErrorBody = try? serializer.decode(data: bodyData)
            }
            
            // Creamos el error de servicio con el Dto tipado listo para la UI/Presenters
            finalServiceError = ServiceError<Failure>(type: networkError.type, body: decodedErrorBody)
            
            // Si el error de red no debe loguearse (como las cancelaciones explícitas), capamos el reporte aquí
            if !networkError.logged { return finalServiceError }
            
        default:
            finalServiceError = ServiceError<Failure>(type: .unknown)
            extraInfo["Context"] = "Error no controlado o fuera del dominio de red/parseo."
        }
        
        // 3. Reporte único centralizado
        reportFailure(error: error, serviceErrorType: finalServiceError.type, info: extraInfo)
        
        return finalServiceError
    }
    
    private func reportFailure(error: Error, serviceErrorType: ServiceErrorType, info: [String: Any]) {
        // Formateamos un contexto de red súper rico para la pestaña de "Log" o "Keys" de Crashlytics
        let requestContext: [String: Any] = [
            "Request": "[\(api.method.description)] \(api.url?.absoluteString ?? "Invalid URL")",
            "RequestBody": String(data: (try? serializer.encode(api.body)) ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A",
            "RequestData": String(data: api.data ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A",
            "ServiceErrorType": String(describing: serviceErrorType),
        ].merging(info) { $1 }
        
        // Enviamos el reporte
        crash?.report(error: error, userInfo: requestContext)
    }
    
    private func failure(_ error: Error, info: [String: Any] = [:]) {
        let requestContext = [
            "URL": (api.url?.absoluteString ?? "Invalid URL")!,
            "Method": api.method.description,
            "RequestBody": String(data: (try? serializer.encode(api.body)) ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A",
            "RequestData": String(data: api.data ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A"
        ].merging(info) { $1 }
        
        crash?.report(error: error, userInfo: requestContext)
    }
}

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
    @concurrent private func performOperation(
        operation: (APIEndpoint) async throws -> Success
    ) async throws(ServiceError<Failure>) -> Success {
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
        
        throw ServiceError<Failure>.unknown
    }
    
    @concurrent public func request() async throws(ServiceError<Failure>) -> Success {
        try await performOperation() { api in
            let data: Data = try await network.request(api: api)
            guard let decoded: Success = try serializer.decode(data: data) else {
                throw ServiceError<Failure>.decode
            }
            return decoded
        }
    }
    
    @concurrent public func upload() async throws(ServiceError<Failure>) -> Success {
        try await performOperation() { api in
            let data: Data = try await network.upload(api: api, data: api.data ?? Data())
            guard let decoded: Success = try serializer.decode(data: data) else {
                throw ServiceError<Failure>.decode
            }
            return decoded
        }
    }
    
    @concurrent public func file(file: String) async throws(ServiceError<Failure>) -> Success {
        do {
            guard let url = Bundle.main.url(forResource: file, withExtension: nil) else {
                throw ServiceError<Failure>.invalidURL
            }
            let data = try Data(contentsOf: url)
            guard let decoded: Success = try serializer.decode(data: data) else {
                throw ServiceError<Failure>.decode
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
        
        var abstractError: ServiceError<Failure>
        var extraInfo: [String: Any] = [:]
        
        switch error {
        case is AuthError:
            abstractError = .unauthorized(nil)
        case let fileError as FileError:
            switch fileError {
            case .invalidTargetURL:
                abstractError = .storage
            case .removeFailed(_):
                abstractError = .storage
            case .copyFailed(_):
                abstractError = .storage
            }

        case let serializerError as SerializerError:
            switch serializerError {
            case .encoding(_, let info):
                abstractError = .encode
                extraInfo = info
            case .decoding(_, let info):
                abstractError = .encode
                extraInfo = info
            }
            
        case let networkError as NetworkError:
            var decodedErrorBody: Failure? = nil
            
            switch networkError {
            case .http(let statusCode, let data):
                if let data, !data.isEmpty {
                    decodedErrorBody = try? serializer.decode(data: data)
                }
                
                switch statusCode {
                case 400: abstractError = .badRequest(decodedErrorBody)
                case 401: abstractError = .unauthorized(decodedErrorBody)
                case 403: abstractError = .forbidden(decodedErrorBody)
                case 404: abstractError = .notFound(decodedErrorBody)
                case 409: abstractError = .conflict(decodedErrorBody)
                case 500...599: abstractError = .serverError(decodedErrorBody)
                default: abstractError = .unexpectedCode(statusCode: statusCode, body: decodedErrorBody)
                }
                
            case .url(_, let code):
                switch code {
                case .timedOut: abstractError = .timedOut
                case .cancelled: abstractError = .canceled
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: abstractError = .noConnection
                case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted: abstractError = .sslError
                case .cannotFindHost, .dnsLookupFailed: abstractError = .serverUnreachable
                default: abstractError = .unknown
                }
                
            case .noResponse:   abstractError = .noResponse
            case .invalidURL:   abstractError = .invalidURL
            default:            abstractError = .unknown
            }
        default:
            abstractError = ServiceError<Failure>.unknown
        }
        
        reportFailure(error: error, serviceError: abstractError, info: extraInfo)
        
        return abstractError
    }
    
    private func reportFailure(error: Error, serviceError: ServiceError<Failure>, info: [String: Any]) {
        let requestContext: [String: Any] = [
            "RequestURL": "[\(api.method.description)] \(api.url?.absoluteString ?? "Invalid URL")",
            "RequestBody": String(data: (try? serializer.encode(api.body)) ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A",
            "RequestData": String(data: api.data ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A"
        ].merging(info) { $1 }
        
        crash?.report(error: error, userInfo: requestContext)
    }
}


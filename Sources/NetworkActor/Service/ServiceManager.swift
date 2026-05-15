//
//  ServiceManager.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
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
            } catch let error as NetworkError where error.type == .unauthorized {
                guard !(attempt == config.maxRetries), let auth else {
                    failure(error)
                    throw mapError(error)
                }
                
                await auth.invalidate()
            } catch {
                failure(error)
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
        if error is AuthError { return ServiceError<Failure>(type: .unauthorized) }
        if error is EncodingError { return ServiceError<Failure>(type: .encode) }
        if error is DecodingError { return ServiceError<Failure>(type: .decode) }
        
        guard let networkError = error as? NetworkError else {
            return ServiceError<Failure>(type: .unknown)
        }
        
        var decodedErrorBody: Failure? = nil
        if let bodyData = networkError.body {
            decodedErrorBody = try? serializer.decode(data: bodyData)
        }
        
        return ServiceError<Failure>(type: networkError.type, body: decodedErrorBody)
    }

    private func failure(_ error: NetworkError, info: [String: Any] = [:]) {
        guard error.logged else { return }

        failure(error, info: ["Error": String(describing: type(of: error))])
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

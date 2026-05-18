//
//  ServiceManager.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import SwiftUI

public struct ServiceManager<Success: Sendable, Failure: Sendable>: Sendable {
    public var id = UUID().uuidString
    
    public var network: NetworkClient
    public var auth: (any AuthProtocol)? = nil
    public var crash: CrashProtocol? = nil
    public var api: ServicePayload
    public var config: ServiceConfig
    
    private let serializer: Serializer
    
    public init(
        network: NetworkClient,
        auth: (any AuthProtocol)? = nil,
        crash: CrashProtocol? = nil,
        api: ServicePayload,
        serializer: Serializer = .init(),
        config: ServiceConfig = .standard
    ) {
        self.network = network
        self.auth = auth
        self.crash = crash
        self.serializer = serializer
        self.api = api
        self.config = config
    }
    
    // MARK: - Throwing Core Implementation
    private func perform<Output>(
        operation: (APIEndpoint) async throws -> Output
    ) async throws(ServiceError<Failure>) -> Output {
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
    
    public func request() async throws(ServiceError<Failure>) -> Success {
        try await perform() { api in
            let data: Data = try await network.data(api: api)
            guard let decoded: Success = try serializer.decode(data: data) else {
                throw ServiceError<Failure>.decode
            }
            return decoded
        }
    }
    
    public func upload() async throws(ServiceError<Failure>) -> Success {
        try await perform() { api in
            let data: Data = try await network.upload(api: api, data: api.data ?? Data())
            guard let decoded: Success = try serializer.decode(data: data) else {
                throw ServiceError<Failure>.decode
            }
            return decoded
        }
    }
    
    public func download() async throws(ServiceError<Failure>) -> URL {
        try await perform() { api in
            let result = try await network.download(api: api)
            return try FileUtils.copy(url: result.url, to: .cachesDirectory, contentType: result.contentType)
        }
    }

    public func file(file: String) async throws(ServiceError<Failure>) -> Success {
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
    private func prepare(payload: ServicePayload) async throws -> APIEndpoint {
        var api = APIEndpoint(
            method: payload.method,
            host: payload.host,
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
    
    public func cancel() async {
        await network.cancel()
    }
}

// MARK: Error management and reporting
extension ServiceManager {
    private func mapError(_ error: Error) -> ServiceError<Failure> {
        let serviceError: ServiceError<Failure>
        let extraInfo: [String: Any] = [:]
        
        switch error {
        case let serviceErr as ServiceError<Failure>:
            serviceError = serviceErr
        case let networkErr as NetworkError:
            serviceError = ServiceError(from: networkErr, serializer: serializer)
        case let urlError as URLError:
            serviceError = ServiceError(from: NetworkError.url(urlError), serializer: serializer)
        case let authErr as AuthError:
            serviceError = ServiceError(from: authErr)
        case let fileErr as FileError:
            serviceError = ServiceError(from: fileErr)
        case let serializerErr as SerializerError:
            serviceError = ServiceError(from: serializerErr)
            // extraInfo = serializerErr.userInfo
        default:
            serviceError = .unknown
        }
        
        reportFailure(error: error, serviceError: serviceError, info: extraInfo)
        return serviceError
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

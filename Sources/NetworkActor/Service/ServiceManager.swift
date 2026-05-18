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
    public let serializer: Serializer
    public var config: ServiceConfig
    public var api: ServicePayload
    
    public init(
        network: NetworkClient,
        auth: (any AuthProtocol)? = nil,
        crash: CrashProtocol? = nil,
        serializer: Serializer = .init(),
        config: ServiceConfig = .standard,
        api: ServicePayload
    ) {
        self.network = network
        self.auth = auth
        self.crash = crash
        self.serializer = serializer
        self.config = config
        self.api = api
    }
    
    // MARK: - Throwing Core Implementation
    private func perform<Output>(
        operation: (URLRequest, Data?) async throws -> Output
    ) async throws(ServiceError<Failure>) -> Output {
        for attempt in 0...config.maxRetries {
            do {
                return try await operation(try await request, try await data)
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
        try await perform() { request, data in
            let response: Data = try await network.data(for: request)
            guard let decoded: Success = try serializer.decode(data: response) else {
                throw ServiceError<Failure>.decode
            }
            return decoded
        }
    }
    
    public func upload() async throws(ServiceError<Failure>) -> Success {
        try await perform() { request, data in
            guard let data else { throw ServiceError<Failure>.missingUploadData }

            let response: Data = try await network.upload(for: request, data: data)
            guard let decoded: Success = try serializer.decode(data: response) else {
                throw ServiceError<Failure>.decode
            }
            return decoded
        }
    }
    
    public func download() async throws(ServiceError<Failure>) -> URL {
        try await perform() { request, data in
            let response = try await network.download(for: request)
            return try FileUtils.copy(url: response.url, to: .cachesDirectory, contentType: response.contentType)
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
        
    public func cancel() async {
        await network.cancel()
    }
}

extension ServiceManager {
    // MARK: - Private Helpers
    private var request: URLRequest {
        get async throws {
            let payload = api
            
            var api = APIEndpoint(
                method: payload.method,
                host: payload.host,
                path: payload.path,
                params: payload.params,
                headers: payload.headers,
                body: nil,
                timeout: payload.timeout
            )
            
            switch payload.body {
            case .data(let data):
                api.body = data
            case .json(let encodable):
                api.headers.merge(ContentType.json().header) { current, new in new }
                api.body = try serializer.encode(payload.body)
            case .multipart(let multipart):
                api.headers.merge(multipart.header) { current, new in new }
                api.body = nil
            case .empty:
                api.body = nil
            }
            
            if let auth {
                api.headers.merge(try await auth.authHeader) { $1 }
            }
            
            guard let request = api.urlRequest else { throw ServiceError<Failure>.invalidURL }
            
            return request
        }
    }
    
    private var data: Data? {
        get async throws {
            switch api.body {
            case .data(let data): data
            case .json(let encodable): try serializer.encode(encodable)
            case .multipart(let multipart): try multipart.body
            case .empty: nil
            }
        }
    }
}

// MARK: Error management and reporting
extension ServiceManager {
    private func mapError(_ error: Error) -> ServiceError<Failure> {
        let serviceError: ServiceError<Failure>
        var extraInfo: [String: Any] = [:]
        
        switch error {
        case let error as ServiceError<Failure>:
            serviceError = error
        case let error as NetworkError:
            serviceError = ServiceError(from: error, serializer: serializer)
            extraInfo = error.info
        case let error as URLError:
            serviceError = ServiceError(from: NetworkError.url(error), serializer: serializer)
        case let error as AuthError:
            serviceError = ServiceError(from: error)
        case let error as FileError:
            serviceError = ServiceError(from: error)
        case let error as SerializerError:
            serviceError = ServiceError(from: error)
            extraInfo = error.info
        default:
            serviceError = .unknown
        }
        
        report(error: error, info: extraInfo)
        return serviceError
    }
    
    private func report(error: Error, info: [String: Any]) {
        let requestContext: [String: Any] = [
            "RequestURL": "[\(api.method.description)] \(api.url?.absoluteString ?? "Invalid URL")",
            "RequestBody": String(data: (try? serializer.encode(api.body)) ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A",
        ].merging(info) { $1 }
        
        crash?.report(error: error, userInfo: requestContext)
    }
}

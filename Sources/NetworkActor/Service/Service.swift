//
//  Service.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import SwiftUI

public struct Service<Success: Sendable, Failure: Sendable>: Sendable {
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
                return try await operation(try await request, try request.httpBody)
            } catch let error as AuthError {
                guard !(attempt == config.maxRetries), let auth else {
                    throw await mapError(error)
                }
                
                await auth.invalidate()
            } catch {
                throw await mapError(error)
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
    
    public func upload(url: URL) async throws(ServiceError<Failure>) -> Success {
        try await perform() { request, _ in
            let response: Data = try await network.upload(for: request, url: url)
            guard let decoded: Success = try serializer.decode(data: response) else {
                throw ServiceError<Failure>.decode
            }
            return decoded
        }
    }

    public func upload(resumeFrom data: Data) async throws(ServiceError<Failure>) -> Success {
        try await perform() { request, _ in
            let response: Data = try await network.upload(for: request, resumeFrom: data)
            guard let decoded: Success = try serializer.decode(data: response) else {
                throw ServiceError<Failure>.decode
            }
            return decoded
        }
    }
    
    public func download() async throws(ServiceError<Failure>) -> URL {
        try await perform() { request, _ in
            let response = try await network.download(for: request)
            return try FileUtils.copy(url: response.url, to: .cachesDirectory, contentType: response.contentType)
        }
    }
    
    public func download(resumeFrom data: Data) async throws(ServiceError<Failure>) -> URL {
        try await perform() { request, _ in
            let response = try await network.download(for: request, resumeFrom: data)
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
            throw await mapError(error)
        }
    }
        
    public func cancel() async -> Data? {
        await network.cancel()
    }
}

extension Service {
    // MARK: - Private Helpers
    private var request: URLRequest {
        get async throws {
            guard let base = URL(string: api.host),
                  var urlComponents = URLComponents(url: base.appendingPathComponent(api.path), resolvingAgainstBaseURL: true)
            else {
                throw ServiceError<Failure>.invalidURL
            }

            if urlComponents.queryItems != nil {
                urlComponents.queryItems?.append(contentsOf: api.params)
            } else {
                urlComponents.queryItems = api.params
            }

            guard let url = urlComponents.url else { throw ServiceError<Failure>.invalidURL }
            
            var request = URLRequest(url: url)
            request.httpMethod = api.method.rawValue
            if let auth {
                request.allHTTPHeaderFields = api.allHeaders.merging(try await auth.authHeader) { $1 }
            } else {
                request.allHTTPHeaderFields = api.allHeaders
            }
            request.httpBody = try api.data(with: serializer)
            request.timeoutInterval = api.timeout
            
            return request
        }
    }
}

// MARK: Error management and reporting
extension Service {
    private func mapError(_ error: Error) async -> ServiceError<Failure> {
        let serviceError: ServiceError<Failure>
        var extraInfo: [String: Any] = [:]
        extraInfo["RequestURL"] = "[\(api.method.description)] \(api.url?.absoluteString ?? "Invalid URL")"
        extraInfo["RequestBody"] = String(data: (try? api.data(with: serializer)) ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A"

        switch error {
        case let error as ServiceError<Failure>:
            serviceError = error
        case let error as NetworkError:
            let body: Failure? = if let data = error.body, let body: Failure? = try? serializer.decode(data: data) { body } else { nil }
            serviceError = ServiceError(from: error, body: body)
            extraInfo = error.info
        case let error as URLError:
            serviceError = ServiceError(from: NetworkError.url(error))
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
        
        crash?.report(error: error, userInfo: extraInfo)
        
        return serviceError
    }
}

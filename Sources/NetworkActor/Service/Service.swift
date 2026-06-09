//
//  Service.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import SwiftUI

public struct Service<Success: Sendable, Failure: Sendable>: Sendable {
    public let id = UUID().uuidString
    
    public let client: any ClientProtocol
    public let auth: (any AuthProtocol)?
    public let crash: (any CrashProtocol)?
    public let serializer: any SerializerProtocol
    public let config: ServiceConfig
    public let api: ServicePayload
    
    public var progress: AsyncStream<Progress> { client.progress }

    public init(
        client: any ClientProtocol = NetworkClient(session: URLSession.shared),
        auth: (any AuthProtocol)? = nil,
        crash: (any CrashProtocol)? = nil,
        serializer: any SerializerProtocol = Serializer(),
        config: ServiceConfig = .standard,
        api: ServicePayload
    ) {
        self.client = client
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
            } catch let error as ClientError {
                guard error.status == .unauthorized, !(attempt == config.maxRetries), let auth else {
                    throw await mapError(error)
                }
                
                await auth.invalidate()
            } catch {
                throw await mapError(error)
            }
        }
        
        throw ServiceError<Failure>.unknown
    }
    
    public func data() async throws(ServiceError<Failure>) -> Success {
        try await perform() { request, data in
            let response: Data = try await client.data(for: request)
            return try serializer.decode(data: response)
        }
    }
    
    public func upload() async throws(ServiceError<Failure>) -> Success {
        try await perform() { request, data in
            guard let data else { throw ServiceError<Failure>.missingUploadData }

            let response: Data = try await client.upload(for: request, data: data)
            return try serializer.decode(data: response)
        }
    }
    
    public func upload(url: URL) async throws(ServiceError<Failure>) -> Success {
        try await perform() { request, _ in
            let response: Data = try await client.upload(for: request, url: url)
            return try serializer.decode(data: response)
        }
    }

    public func upload(resumeFrom data: Data) async throws(ServiceError<Failure>) -> Success {
        try await perform() { request, _ in
            let response: Data = try await client.upload(for: request, resumeFrom: data)
            return try serializer.decode(data: response)
        }
    }
    
    public func download() async throws(ServiceError<Failure>) -> URL {
        try await perform() { request, _ in
            let response = try await client.download(for: request)
            return try FileUtils.copy(url: response.url, to: .cachesDirectory, contentType: response.contentType)
        }
    }
    
    public func download(resumeFrom data: Data) async throws(ServiceError<Failure>) -> URL {
        try await perform() { request, _ in
            let response = try await client.download(for: request, resumeFrom: data)
            return try FileUtils.copy(url: response.url, to: .cachesDirectory, contentType: response.contentType)
        }
    }

    public func file(file: String) async throws(ServiceError<Failure>) -> Success {
        do {
            guard let url = Bundle.main.url(forResource: file, withExtension: nil) else {
                throw ServiceError<Failure>.invalidURL
            }
            let data = try Data(contentsOf: url)
            return try serializer.decode(data: data)
        } catch {
            throw await mapError(error)
        }
    }
        
    public func cancel() async -> Data? {
        await client.cancel()
    }
}

extension Service {
    // MARK: - Private Helpers
    private var defaultAcceptHeader: [String: String]? {
        switch Success.self {
        case is Data.Type: ["Accept": "application/octet-stream"]
        case is String.Type, is Bool.Type: ["Accept": "text/plain; charset=utf-8"]
        case is Void.Type: ["Accept": "*/*"]
        #if canImport(UIKit)
        case is UIImage.Type: ["Accept": "image/*"]
        #endif
        case is Codable.Type: ["Accept": "application/json"]
        default: nil
        }
    }

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

            var headers = api.allHeaders
            if let defaultAcceptHeader, headers["Accept"] == nil {
                headers.merge(defaultAcceptHeader) { current, _ in current }
            }

            if let auth {
                headers = headers.merging(try await auth.authHeader) { _, new in new }
            }

            request.allHTTPHeaderFields = headers
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
        extraInfo["Endpoint"] = "[\(api.method.description)] \(api.url?.absoluteString ?? "Invalid URL")"
        extraInfo["RequestBody"] = String(data: (try? api.data(with: serializer)) ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A"

        switch error {
        case let error as ServiceError<Failure>:
            serviceError = error
        case let error as ClientError:
            let body: Failure? = if let data = error.body, let body: Failure? = try? serializer.decode(data: data) { body } else { nil }
            serviceError = ServiceError(from: error, body: body)
            extraInfo.merge(error.info) { $1 }
        case let error as URLError:
            serviceError = ServiceError(from: ClientError.url(error))
        case let error as AuthError:
            serviceError = ServiceError(from: error)
        case let error as FileError:
            serviceError = ServiceError(from: error)
        case let error as SerializerError:
            serviceError = ServiceError(from: error)
            extraInfo.merge(error.info) { $1 }
        default:
            serviceError = .unknown
        }
        
        guard serviceError != .cancelled else { return serviceError }
        
        crash?.report(error: serviceError, userInfo: extraInfo)
        
        return serviceError
    }
}

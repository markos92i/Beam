//
//  Service.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct Service<Success: Sendable, Failure: Sendable>: Sendable {
    public let id = UUID().uuidString

    private let log: Logger
    public let client: any ClientProtocol
    public let auth: (any AuthProtocol)?
    public let crash: (any CrashProtocol)?
    public let serializer: any SerializerProtocol
    public let config: ServiceConfig
    public let api: ServicePayload
    
    public var progress: AsyncStream<Progress> { client.progress }

    public init(
        client: any ClientProtocol = Client(session: URLSession.shared),
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
        self.log = Logger(output: crash)
    }
    
    // MARK: - Throwing Core Implementation
    private func perform<Output>(
        operation: (URLRequest) async throws -> Output
    ) async throws(ServiceError<Failure>) -> Output {
        for attempt in 0...config.maxRetries {
            do {
                #if DEBUG
                if attempt > 0 { log.retry(attempt: attempt, maxRetries: config.maxRetries) }
                #endif
                let result = try await operation(try await request)
                return result
            } catch let error as ClientError {
                if error.status == .unauthorized { await auth?.invalidate() }
                
                guard attempt < config.maxRetries, error.isRetryable else {
                    throw await mapError(error, attempt: attempt)
                }
            } catch {
                throw await mapError(error, attempt: attempt)
            }
        }
        
        throw ServiceError<Failure>.unknown
    }
    
    public func data() async throws(ServiceError<Failure>) -> Success {
        if let cacheFile = api.cacheFile { return try await file(file: cacheFile) }
        return try await perform() { request in
            var request = request
            request.httpBody = try api.data(with: serializer)
            let response: Data = try await client.data(for: request)
            return try serializer.decode(data: response)
        }
    }
    
    public func upload() async throws(ServiceError<Failure>) -> Success {
        try await perform() { request in
            guard let body = try api.data(with: serializer) else { throw ServiceError<Failure>.missingUploadData }
            let response: Data = try await client.upload(for: request, data: body)
            return try serializer.decode(data: response)
        }
    }
    
    public func upload(url: URL) async throws(ServiceError<Failure>) -> Success {
        try await perform() { request in
            let response: Data = try await client.upload(for: request, url: url)
            return try serializer.decode(data: response)
        }
    }

    public func upload(resumeFrom data: Data) async throws(ServiceError<Failure>) -> Success {
        try await perform() { request in
            let response: Data = try await client.upload(for: request, resumeFrom: data)
            return try serializer.decode(data: response)
        }
    }
    
    public func download() async throws(ServiceError<Failure>) -> URL {
        try await perform() { request in
            let response = try await client.download(for: request)
            return try FileUtils.copy(url: response.url, to: .cachesDirectory, contentType: response.contentType)
        }
    }
    
    public func download(resumeFrom data: Data) async throws(ServiceError<Failure>) -> URL {
        try await perform() { request in
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
            throw await mapError(error, attempt: 0)
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
            request.timeoutInterval = api.timeout
            
            return request
        }
    }
}

// MARK: Error management and reporting
extension Service {
    private func mapError(_ error: Error, attempt: Int) async -> ServiceError<Failure> {
        let serviceError = parseError(error)
        
        guard !serviceError.isSilent else { return serviceError }

        log.error(serviceError, source: error, attempt: attempt)
        reportError(serviceError, error: error, attempt: attempt)
        
        return serviceError
    }

    private func parseError(_ error: Error) -> ServiceError<Failure> {
        switch error {
        case let error as ServiceError<Failure>:
            return error
        case let error as ClientError:
            let body: Failure? = if let data = error.body, let decoded: Failure? = try? serializer.decode(data: data) { decoded } else { nil }
            return ServiceError(from: error, body: body)
        case let error as URLError:
            return ServiceError(from: ClientError.url(error))
        case let error as AuthError:
            return ServiceError(from: error)
        case let error as FileError:
            return ServiceError(from: error)
        case let error as SerializerError:
            return ServiceError(from: error)
        default:
            return .unknown
        }
    }

    private func reportError(_ serviceError: ServiceError<Failure>, error: Error, attempt: Int) {
        var info: [String: Any] = [
            "Method": api.method.description,
            "Host": api.host,
            "Path": api.path,
            "Attempt": attempt
        ]

        if let error = error as? InfoError { info.merge(error.info) { $1 } }

        let sanitizedPath = api.path.replacing(/\/\d+/, with: "/{id}")
        let description: String = switch error {
        case let error as SerializerError: error.info.values.first.map { "\($0)" } ?? serviceError.name
        case let error as ClientError: error.description ?? serviceError.name
        default: serviceError.name
        }

        let reportError = NSError(
            domain: "\(api.method) \(sanitizedPath) — \(serviceError.name)",
            code: serviceError.id,
            userInfo: info.merging([NSLocalizedDescriptionKey: description]) { $1 }.mapValues { "\($0)" }
        )
        crash?.report(error: reportError, userInfo: info)
    }
}

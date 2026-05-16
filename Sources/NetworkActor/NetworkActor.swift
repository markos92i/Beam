//
//  NetworkActor.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Protocol Definition
protocol NetworkProtocol: Actor {
    func request(api: APIEndpoint) async throws -> Data
    func upload(api: APIEndpoint, data: Data) async throws -> Data
    func download(api: APIEndpoint) async throws -> URL
    
    var progress: AsyncStream<Progress> { get }
}

public actor NetworkActor: NetworkProtocol {
    public let uuid = UUID().uuidString
    
    private let logger: Logger = Logger()

    private let delegate: NetworkDelegate
    private let session: URLSession
    
    private let progressContinuation: AsyncStream<Progress>.Continuation
    internal let progress: AsyncStream<Progress>
    
    public static let queue = NetworkQueue()

    public static let config: URLSessionConfiguration = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.urlCache = nil
        return config
    }()

    public init(
        configuration: URLSessionConfiguration = config,
        certificates: [Data] = []
    ) {
        let (stream, continuation) = AsyncStream<Progress>.makeStream()
        self.progress = stream
        self.progressContinuation = continuation

        self.delegate = .init(certificates: certificates, continuation: continuation)
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    
    deinit {
        progressContinuation.finish()
    }
    
    private func executeOperation<T>(
        api: APIEndpoint,
        operation: (URLRequest) async throws -> (T, URLResponse)
    ) async throws(NetworkError) -> (T, HTTPURLResponse) {
        guard let request = api.urlRequest else { throw .invalidURL }
        
        logger.debug("request path: [\(api.method)] \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody {
            logger.debug("request body: \(String(data: body, encoding: .utf8) ?? "")")
        }
        
        do {
            let (responseData, response) = try await operation(request)
            await NetworkActor.queue.remove(session)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.noResponse
            }
            
            logger.debug("response statusCode: \(httpResponse.statusCode)")
            
            return (responseData, httpResponse)
        } catch let error as URLError {
            logger.error("URLError: \(error.code.rawValue) - \(error.localizedDescription)")
            await NetworkActor.queue.remove(session)
            throw .url(error)
        } catch let error as NetworkError {
            logger.error("NetworkError: \(error.statusCode) - \(error.localizedDescription)")
            await NetworkActor.queue.remove(session)
            throw error
        } catch {
            logger.error("UnknownError: \(error.localizedDescription)")
            await NetworkActor.queue.remove(session)
            throw NetworkError.unknown(error)
        }
    }
    
    // MARK: - Public API
    public func request(api: APIEndpoint) async throws(NetworkError) -> Data {
        let (data, response) = try await executeOperation(api: api) { request in
            try await session.data(for: request)
        }
        
        logger.debug("response body: \(JSONHelper.prettyString(from: data) ?? "")")
        guard (200...299).contains(response.statusCode) else { throw .http(code: response.statusCode, data: data) }
        
        return data
    }
    
    public func upload(api: APIEndpoint, data: Data) async throws(NetworkError) -> Data {
        let (responseData, response) = try await executeOperation(api: api) { request in
            try await session.upload(for: request, from: data)
        }
        
        guard (200...299).contains(response.statusCode) else { throw .http(code: response.statusCode, data: responseData) }

        return responseData
    }
    
    public func download(api: APIEndpoint) async throws(NetworkError) -> URL {
        let (url, response) = try await executeOperation(api: api) { request in
            try await session.download(for: request)
        }
        
        guard (200...299).contains(response.statusCode) else { throw .http(code: response.statusCode, data: nil) }
        
        do {
            return try FileUtils.copy(url: url, to: .cachesDirectory, contentType: response.contentType)
        } catch {
            throw NetworkError(fileError: error)
        }
    }

    public func cancel() async {
        await NetworkActor.queue.cancel(session)
    }
    
    private func handleAndThrow(_ error: NetworkError, function: String = #function) async throws -> Never {
        logger.error("[\(function)] \(error.description ?? error.localizedDescription)")
        throw error
    }
}

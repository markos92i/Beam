//
//  NetworkActor.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//

import SwiftUI

// MARK: - Protocol Definition
protocol NetworkProtocol: Actor {
    func request(api: APIEndpoint) async throws(NetworkError) -> Data
    func upload(api: APIEndpoint, data: Data) async throws(NetworkError) -> Data
    func download(api: APIEndpoint) async throws(NetworkError) -> (url: URL, contentType: String)
    
    var progress: AsyncStream<Progress> { get }
}

public actor NetworkActor: NetworkProtocol {
    public let uuid = UUID().uuidString
    
    private let logger: Logger = Logger()
    private let session: URLSession
    private let certificates: [Data]
    
    private let progressContinuation: AsyncStream<Progress>.Continuation
    internal let progress: AsyncStream<Progress>
    
    public static let queue = NetworkQueue()

    public init(
        configuration: URLSessionConfiguration = .default,
        certificates: [Data] = []
    ) {
        self.session = URLSession(configuration: configuration)
        self.certificates = certificates
        
        let (stream, continuation) = AsyncStream<Progress>.makeStream()
        self.progress = stream
        self.progressContinuation = continuation
    }
    
    deinit {
        progressContinuation.finish()
    }
    
    private func execute<T>(
        api: APIEndpoint,
        operation: (URLRequest, URLSessionTaskDelegate) async throws -> (T, URLResponse)
    ) async throws(NetworkError) -> (T, HTTPURLResponse) {
        guard let request = api.urlRequest else { throw .invalidURL }
        
        logger.debug("request path: [\(request.httpMethod ?? "")] \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody {
            logger.debug("request body: \(String(data: body, encoding: .utf8) ?? "")")
        }
        
        do {
            defer { onTaskCompleted() }
            let delegate = NetworkDelegate(certificates: certificates) { [weak self] task in
                Task { [weak self] in await self?.onTaskCreated(task: task) }
            }
            
            let (responseData, response) = try await operation(request, delegate)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.noResponse
            }
            
            logger.debug("response statusCode: \(httpResponse.statusCode)")
            
            return (responseData, httpResponse)
        } catch let error as URLError {
            logger.error("URLError: \(error.code.rawValue) - \(error.localizedDescription)")
            throw .url(error)
        } catch let error as NetworkError {
            logger.error("NetworkError: \(error.statusCode) - \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("UnknownError: \(error.localizedDescription)")
            throw NetworkError.unknown(error)
        }
    }
    
    // MARK: - Public API
    public func request(api: APIEndpoint) async throws(NetworkError) -> Data {
        let (data, response) = try await execute(api: api) { request, delegate in
            return try await session.data(for: request, delegate: delegate)
        }
        
        logger.debug("response body: \(JSONHelper.prettyString(from: data) ?? "")")
        guard (200...299).contains(response.statusCode) else { throw .http(code: response.statusCode, data: data) }
        
        return data
    }
    
    public func upload(api: APIEndpoint, data: Data) async throws(NetworkError) -> Data {
        let (responseData, response) = try await execute(api: api) { request, delegate in
            try await session.upload(for: request, from: data, delegate: delegate)
        }
        
        guard (200...299).contains(response.statusCode) else { throw .http(code: response.statusCode, data: responseData) }

        return responseData
    }
    
    public func download(api: APIEndpoint) async throws(NetworkError) -> (url: URL, contentType: String) {
        let (url, response) = try await execute(api: api) { request, delegate in
            try await session.download(for: request, delegate: delegate)
        }
        
        guard (200...299).contains(response.statusCode) else { throw .http(code: response.statusCode, data: nil) }
        
        return (url, response.contentType)
    }
        
    public func cancel() async {
        await NetworkActor.queue.cancel(id: uuid)
    }
    
    private func handleAndThrow(_ error: NetworkError, function: String = #function) async throws -> Never {
        logger.error("[\(function)] \(error.description ?? error.localizedDescription)")
        throw error
    }
    
    // MARK: Task management
    func onTaskCreated(task: URLSessionTask) {
        self.progressContinuation.yield(task.progress)
        
        Task { await NetworkActor.queue.append(id: uuid, task: task) }
    }
    
    func onTaskCompleted() {
        Task { await NetworkActor.queue.remove(id: uuid) }
    }

}

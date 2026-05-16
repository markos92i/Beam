//
//  NetworkActor.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//

import SwiftUI

// MARK: - Protocol Definition
protocol NetworkProtocol: Actor {
    func data(api: APIEndpoint) async throws(NetworkError) -> Data
    func upload(api: APIEndpoint, data: Data) async throws(NetworkError) -> Data
    func download(api: APIEndpoint) async throws(NetworkError) -> (url: URL, contentType: String)
    
    var progress: Progress { get async }
}

public actor NetworkActor: NetworkProtocol {
    public let uuid = UUID().uuidString
    
    private let logger: Logger = Logger()
    private let session: URLSession
    private let certificates: [Data]
    
    private var continuation: CheckedContinuation<Progress, Never>?
    public var progress: Progress { get async { await withCheckedContinuation { continuation = $0 } } }

    private var tasks: [String: URLSessionTask] = [:]

    public init(
        configuration: URLSessionConfiguration = .default,
        certificates: [Data] = []
    ) {
        self.session = URLSession(configuration: configuration)
        self.certificates = certificates
    }
        
    private func execute<T>(
        api: APIEndpoint,
        operation: (URLRequest, URLSessionTaskDelegate) async throws -> (T, URLResponse)
    ) async throws(NetworkError) -> (T, HTTPURLResponse) {
        guard let request = api.urlRequest else { throw .invalidURL }
        
        logger.debug("[\(request.httpMethod ?? "")] \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody {
            logger.debug("[REQUEST]: \(String(data: body, encoding: .utf8) ?? "")")
        }
        
        do {
            defer { onTaskCompleted() }
            let delegate = NetworkDelegate(certificates: certificates) { [weak self] task in
                Task { [weak self] in await self?.onTaskCreated(task: task) }
            }
            
            let (value, response) = try await operation(request, delegate)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.noResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.http(code: httpResponse.statusCode, data: value as? Data)
            }

            logger.debug("[\(request.httpMethod ?? "")] \(request.url?.absoluteString ?? "")")
            logger.debug("[RESPONSE]: \(httpResponse.statusCode)")
            logger.debug("[RESPONSE]:\n\(JSONHelper.prettyString(from: (value as? Data) ?? Data()) ?? "")")

            return (value, httpResponse)
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
    public func data(api: APIEndpoint) async throws(NetworkError) -> Data {
        let (result, _) = try await execute(api: api) { request, delegate in
            return try await session.data(for: request, delegate: delegate)
        }
        return result
    }
    
    public func upload(api: APIEndpoint, data: Data) async throws(NetworkError) -> Data {
        let (result, _) = try await execute(api: api) { request, delegate in
            try await session.upload(for: request, from: data, delegate: delegate)
        }
        return result
    }
    
    public func download(api: APIEndpoint) async throws(NetworkError) -> (url: URL, contentType: String) {
        let (result, response) = try await execute(api: api) { request, delegate in
            try await session.download(for: request, delegate: delegate)
        }
        return (result, response.contentType)
    }
}

extension NetworkActor {
    public func cancel() async {
        tasks[uuid]?.cancel()
        tasks.removeValue(forKey: uuid)
    }

    // MARK: Task management
    private func onTaskCreated(task: URLSessionTask) {
        continuation?.resume(returning: task.progress)
        
        tasks[uuid] = task
    }
    
    private func onTaskCompleted() {
        tasks.removeValue(forKey: uuid)
    }
}

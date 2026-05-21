//
//  NetworkClient.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//

import Foundation

// MARK: - Protocol Definition
protocol NetworkProtocol: Actor {
    func upload(for: URLRequest, data: Data) async throws(NetworkError) -> Data
    func upload(for request: URLRequest, resumeFrom data: Data) async throws(NetworkError) -> Data
    func download(for: URLRequest) async throws(NetworkError) -> (url: URL, contentType: String)
    func download(for request: URLRequest, resumeFrom data: Data) async throws(NetworkError) -> (url: URL, contentType: String)
    func cancel() async -> Data?

    var progress: AsyncStream<Progress> { get }
}

public actor NetworkClient: NetworkProtocol {
    private let logger: Logger = Logger()
    private let session: URLSession
    private let certificates: [Data]
    
    private var task: URLSessionTask?
    private let progressContinuation: AsyncStream<Progress>.Continuation
    public let progress: AsyncStream<Progress>

    public init(
        session: URLSession = .shared,
        certificates: [Data] = []
    ) {
        self.session = session
        self.certificates = certificates
        
        let (stream, continuation) = AsyncStream<Progress>.makeStream()
        self.progress = stream
        self.progressContinuation = continuation
    }
    
    deinit {
        progressContinuation.finish()
    }

    private func execute<T>(
        for request: URLRequest,
        operation: (URLSessionTaskDelegate) async throws -> (T, URLResponse)
    ) async throws(NetworkError) -> (T, HTTPURLResponse) {
        logger.debug("[\(request.httpMethod ?? "")] \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody, !body.isEmpty {
            logger.debug("[REQUEST]: \(String(data: body, encoding: .utf8) ?? "")")
        }
        
        do {
            return try await withTaskCancellationHandler {
                defer { onTaskCompleted() }
                
                let delegate = NetworkDelegate(certificates: certificates) { [weak self] task in
                    Task { [weak self] in await self?.onTaskCreated(task: task) }
                }
                
                let (value, response) = try await operation(delegate)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.noResponse
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw NetworkError.http(code: httpResponse.statusCode, body: value as? Data)
                }
                
                logger.debug("[\(request.httpMethod ?? "")] \(request.url?.absoluteString ?? "")")
                logger.debug("[RESPONSE]: \(httpResponse.statusCode)")
                if let data = value as? Data {
                    logger.debug("[RESPONSE BODY]:\n\(JSONHelper.prettyString(from: data) ?? "Formato inválido")")
                } else if let url = value as? URL {
                    logger.debug("[RESPONSE FILE]: Archivo descargado en \(url.path)")
                }
                return (value, httpResponse)
            } onCancel: {
                Task { [weak self] in await self?.onTaskCompleted() }
            }
        } catch let error as URLError {
            logger.error("URLError: \(error.code.rawValue) - \(error.localizedDescription)")
            throw NetworkError.url(error)
        } catch let error as NetworkError {
            logger.error("NetworkError: \(error.statusCode) - \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("UnknownError: \(error.localizedDescription)")
            throw NetworkError.unknown(error)
        }
    }
    
    // MARK: - Public API
    public func data(for request: URLRequest) async throws(NetworkError) -> Data {
        let (result, _) = try await execute(for: request) { delegate in
            return try await session.data(for: request, delegate: delegate)
        }
        return result
    }
    
    public func upload(for request: URLRequest, data: Data) async throws(NetworkError) -> Data {
        let (result, _) = try await execute(for: request) { delegate in
            try await session.upload(for: request, from: data, delegate: delegate)
        }
        return result
    }
    
    public func upload(for request: URLRequest, url: URL) async throws(NetworkError) -> Data {
        let (result, _) = try await execute(for: request) { delegate in
            try await session.upload(for: request, fromFile: url, delegate: delegate)
        }
        return result
    }

    public func upload(for request: URLRequest, resumeFrom data: Data) async throws(NetworkError) -> Data {
        let (result, _) = try await execute(for: request) { delegate in
            try await session.upload(resumeFrom: data, delegate: delegate)
        }
        return result
    }
    
    public func download(for request: URLRequest) async throws(NetworkError) -> (url: URL, contentType: String) {
        let (result, response) = try await execute(for: request) { delegate in
            try await session.download(for: request, delegate: delegate)
        }
        return (result, response.mimeType ?? "application/octet-stream")
    }
    
    public func download(for request: URLRequest, resumeFrom data: Data) async throws(NetworkError) -> (url: URL, contentType: String) {
        let (result, response) = try await execute(for: request) { delegate in
            return try await session.download(resumeFrom: data, delegate: delegate)
        }
        return (result, response.mimeType ?? "application/octet-stream")
    }
}

extension NetworkClient {
    public func cancel() async -> Data? {
        defer { task = nil }
        
        switch task {
        case let task as URLSessionUploadTask:
            return await task.cancelByProducingResumeData()
        case let task as URLSessionDownloadTask:
            return await task.cancelByProducingResumeData()
        default:
            task?.cancel()
            return nil
        }
    }
}

// MARK: Task management
extension NetworkClient {
    private func onTaskCreated(task: URLSessionTask) {
        self.task = task
        progressContinuation.yield(task.progress)
    }
    
    private func onTaskCompleted() {
        task = nil
    }
}

// MARK: URLSession extension
extension URLSession {
    func upload(resumeFrom data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let task = self.uploadTask(withResumeData: data) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.delegate = delegate
            task.resume()
        }
    }
}

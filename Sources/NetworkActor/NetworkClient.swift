//
//  NetworkClient.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//

import Foundation

// MARK: - Protocol Definition
public protocol ClientProtocol: Sendable {
    func data(for: URLRequest) async throws(ClientError) -> Data
    func upload(for: URLRequest, data: Data) async throws(ClientError) -> Data
    func upload(for request: URLRequest, url: URL) async throws(ClientError) -> Data
    func upload(for request: URLRequest, resumeFrom data: Data) async throws(ClientError) -> Data
    func download(for: URLRequest) async throws(ClientError) -> (url: URL, contentType: String)
    func download(for request: URLRequest, resumeFrom data: Data) async throws(ClientError) -> (url: URL, contentType: String)
    func cancel() async -> Data?

    var progress: AsyncStream<Progress> { get }
}

public actor NetworkClient: ClientProtocol {
    private let logger: Logger = Logger()
    private let session: any NetworkSession
    private let certificates: [Data]
    
    private var task: URLSessionTask?
    private let progressContinuation: AsyncStream<Progress>.Continuation
    public let progress: AsyncStream<Progress>

    public init(
        session: any NetworkSession = URLSession.shared,
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
    ) async throws(ClientError) -> (T, HTTPURLResponse) {
        do {
            logger.debug("[\(request.httpMethod ?? "")] \(request.url?.absoluteString ?? "")")
            if let body = request.httpBody, !body.isEmpty {
                logger.debug("[REQUEST]: \(String(data: body, encoding: .utf8) ?? "")")
            }

            return try await withTaskCancellationHandler {
                defer { onTaskCompleted() }
                
                let delegate = NetworkDelegate(certificates: certificates) { [weak self] task in
                    Task { [weak self] in await self?.onTaskCreated(task: task) }
                }
                
                let (value, response) = try await operation(delegate)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ClientError.noResponse
                }
                
                guard let status = HTTPStatus(rawValue: httpResponse.statusCode) else {
                    throw ClientError.http(status: .undefined, body: value as? Data)
                }
                
                guard status.type == .success else {
                    throw ClientError.http(status: status, body: value as? Data)
                }

                logger.debug("[\(request.httpMethod ?? "")] \(request.url?.absoluteString ?? "")")
                logger.debug("[RESPONSE]: \(httpResponse.statusCode)")
                if let data = value as? Data {
                    logger.debug("[RESPONSE BODY]:\n\(JSONHelper.prettyString(from: data) ?? "Invalid format")")
                } else if let url = value as? URL {
                    logger.debug("[RESPONSE FILE]: \(url.path)")
                }
                return (value, httpResponse)
            } onCancel: {
                Task { [weak self] in await self?.onTaskCancelled() }
            }
        } catch let error as URLError {
            logger.error("URLError: \(error.code.rawValue) - \(error.localizedDescription)")
            throw ClientError.url(error)
        } catch let error as ClientError {
            logger.error("NetworkError: \(error.status.rawValue) - \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("UnknownError: \(error.localizedDescription)")
            throw ClientError.unknown(error)
        }
    }
    
    // MARK: - Public API
    public func data(for request: URLRequest) async throws(ClientError) -> Data {
        let (result, _) = try await execute(for: request) { delegate in
            try await session.data(for: request, delegate: delegate)
        }
        return result
    }
    
    public func upload(for request: URLRequest, data: Data) async throws(ClientError) -> Data {
        let (result, _) = try await execute(for: request) { delegate in
            try await session.upload(for: request, from: data, delegate: delegate)
        }
        return result
    }
    
    public func upload(for request: URLRequest, url: URL) async throws(ClientError) -> Data {
        let (result, _) = try await execute(for: request) { delegate in
            try await session.upload(for: request, fromFile: url, delegate: delegate)
        }
        return result
    }

    public func upload(for request: URLRequest, resumeFrom data: Data) async throws(ClientError) -> Data {
        let (result, _) = try await execute(for: request) { delegate in
            try await session.upload(resumeFrom: data, delegate: delegate)
        }
        return result
    }
    
    public func download(for request: URLRequest) async throws(ClientError) -> (url: URL, contentType: String) {
        let (result, response) = try await execute(for: request) { delegate in
            try await session.download(for: request, delegate: delegate)
        }
        return (result, response.mimeType ?? ContentType.data.value)
    }
    
    public func download(for request: URLRequest, resumeFrom data: Data) async throws(ClientError) -> (url: URL, contentType: String) {
        let (result, response) = try await execute(for: request) { delegate in
            try await session.download(resumeFrom: data, delegate: delegate)
        }
        return (result, response.mimeType ?? ContentType.data.value)
    }
}

// MARK: User initiated cancel
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
    
    private func onTaskCancelled() {
        task?.cancel()
        task = nil
    }

    private func onTaskCompleted() {
        task = nil
    }
}

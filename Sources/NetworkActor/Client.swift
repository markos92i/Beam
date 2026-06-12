//
//  Client.swift
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

public actor Client: ClientProtocol {
    private let log: Logger
    private let session: any NetworkSession
    private let certificates: [Data]

    private var task: URLSessionTask?
    private let progressContinuation: AsyncStream<Progress>.Continuation
    public let progress: AsyncStream<Progress>

    public init(
        session: any NetworkSession = URLSession.shared,
        certificates: [Data] = [],
        crash: (any CrashProtocol)? = nil
    ) {
        self.session = session
        self.certificates = certificates
        self.log = Logger(output: crash)

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
        let rid = String(UUID().uuidString.prefix(4))
        let start = Date()
        do {
            log.request(rid: rid, request: request)

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
                    log.response(rid: rid, status: status.rawValue, headers: httpResponse.allHeaderFields as? [String: String] ?? [:], value: value, start: start)
                    throw ClientError.http(status: status, body: value as? Data)
                }

                log.response(rid: rid, status: httpResponse.statusCode, headers: httpResponse.allHeaderFields as? [String: String] ?? [:], value: value, start: start)
                return (value, httpResponse)
            } onCancel: {
                Task { [weak self] in await self?.onTaskCancelled() }
            }
        } catch let error as URLError {
            throw ClientError.url(error)
        } catch let error as ClientError {
            throw error
        } catch is CancellationError {
            throw ClientError.cancelled
        } catch {
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

    // MARK: - Cancel
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

// MARK: - Task management
extension Client {
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

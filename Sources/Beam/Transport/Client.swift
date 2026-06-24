//
//  Client.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//

import Foundation

public actor Client: Identifiable {
    public let id: String
    private let log: BeamLogger
    private let session: any SessionProtocol

    private var task: URLSessionTask?

    /// Parent progress object exposed to consumers. When a task starts,
    /// its `task.progress` is added as a child so this object automatically
    /// reflects transfer progress via Foundation's Progress tree.
    public nonisolated let progress: Progress

    public init(
        id: String = String(UUID().uuidString.prefix(4)),
        session: any SessionProtocol = URLSession.shared
    ) {
        self.session = session
        self.log = BeamLogger()
        self.id = id
        self.progress = Progress(totalUnitCount: 1)
    }

    private func execute<T>(
        for request: URLRequest,
        operation: (URLSessionTaskDelegate) async throws -> (T, URLResponse)
    ) async throws(TransportError) -> (T, HTTPURLResponse) {
        let start = Date()
        let signpostState = log.beginRequest(rid: id, method: request.httpMethod ?? "", path: request.url?.path() ?? "")

        do {
            log.log(.request(rid: id, method: request.httpMethod ?? "", url: request.url, headers: request.allHTTPHeaderFields, body: request.httpBody))

            let delegate = TaskTrackingDelegate { [weak self] task in
                Task { [weak self] in await self?.onTaskCreated(task: task) }
            }

            let (value, response) = try await operation(delegate)

            guard let httpResponse = response as? HTTPURLResponse else {
                log.endRequest(signpostState, status: 0)
                throw TransportError.noResponse
            }

            let body: LogEvent.Body = if let data = value as? Data { .data(data) }
                                      else if let url = value as? URL { .file(url) }
                                      else { .none }
            log.log(.response(rid: id, status: httpResponse.statusCode, headers: httpResponse.allHeaderFields as? [String: String] ?? [:], body: body, start: start))
            log.endRequest(signpostState, status: httpResponse.statusCode)
            
            let status = HTTPStatus(rawValue: httpResponse.statusCode) ?? .undefined

            guard status.type == .success else {
                throw TransportError.http(status: status, body: value as? Data)
            }

            return (value, httpResponse)
        } catch let error as URLError {
            log.endRequest(signpostState, status: -1)
            throw TransportError.url(error)
        } catch let error as TransportError {
            throw error
        } catch is CancellationError {
            log.endRequest(signpostState, status: -2)
            throw TransportError.cancelled
        } catch {
            log.endRequest(signpostState, status: -3)
            throw TransportError.unknown(error)
        }
    }

    // MARK: - Public async API
    public func bytes(for request: URLRequest) async throws(TransportError) -> (URLSession.AsyncBytes, HTTPURLResponse) {
        try await execute(for: request) { delegate in
            try await session.bytes(for: request, delegate: delegate)
        }
    }

    public func data(for request: URLRequest) async throws(TransportError) -> (Data, HTTPURLResponse) {
        defer { onTaskCompleted() }
        return try await execute(for: request) { delegate in
            try await session.data(for: request, delegate: delegate)
        }
    }

    public func upload(for request: URLRequest, data: Data) async throws(TransportError) -> (Data, HTTPURLResponse) {
        defer { onTaskCompleted() }
        return try await execute(for: request) { delegate in
            try await session.upload(for: request, from: data, delegate: delegate)
        }
    }

    public func upload(for request: URLRequest, url: URL) async throws(TransportError) -> (Data, HTTPURLResponse) {
        defer { onTaskCompleted() }
        return try await execute(for: request) { delegate in
            try await session.upload(for: request, fromFile: url, delegate: delegate)
        }
    }

    public func upload(for request: URLRequest, resumeFrom data: Data) async throws(TransportError) -> (Data, HTTPURLResponse) {
        defer { onTaskCompleted() }
        return try await execute(for: request) { delegate in
            try await session.upload(resumeFrom: data, delegate: delegate)
        }
    }

    public func download(for request: URLRequest) async throws(TransportError) -> (url: URL, response: HTTPURLResponse) {
        defer { onTaskCompleted() }
        let (url, httpResponse) = try await execute(for: request) { delegate in
            try await session.download(for: request, delegate: delegate)
        }
        return (url: url, response: httpResponse)
    }

    public func download(for request: URLRequest, resumeFrom data: Data) async throws(TransportError) -> (url: URL, response: HTTPURLResponse) {
        defer { onTaskCompleted() }
        let (url, httpResponse) = try await execute(for: request) { delegate in
            try await session.download(resumeFrom: data, delegate: delegate)
        }
        return (url: url, response: httpResponse)
    }

    // MARK: - Public task API (background-compatible)
    public func downloadTask(for request: URLRequest) async throws(TransportError) -> (url: URL, response: HTTPURLResponse) {
        defer { onTaskCompleted() }
        let (url, httpResponse) = try await execute(for: request) { _ in
            let task = session.downloadTask(with: request)
            onTaskCreated(task: task)
            return try await withCheckedThrowingContinuation { continuation in
                task.delegate = DownloadTransferDelegate(continuation: continuation)
                task.resume()
            }
        }
        return (url: url, response: httpResponse)
    }

    public func downloadTask(for request: URLRequest, resumeFrom data: Data) async throws(TransportError) -> (url: URL, response: HTTPURLResponse) {
        defer { onTaskCompleted() }
        let (url, httpResponse) = try await execute(for: request) { _ in
            let task = session.downloadTask(withResumeData: data)
            onTaskCreated(task: task)
            return try await withCheckedThrowingContinuation { continuation in
                task.delegate = DownloadTransferDelegate(continuation: continuation)
                task.resume()
            }
        }
        return (url: url, response: httpResponse)
    }

    public func uploadTask(for request: URLRequest, from data: Data) async throws(TransportError) -> (Data, HTTPURLResponse) {
        defer { onTaskCompleted() }
        return try await execute(for: request) { _ in
            let task = session.uploadTask(with: request, from: data)
            onTaskCreated(task: task)
            return try await withCheckedThrowingContinuation { continuation in
                task.delegate = UploadTransferDelegate(continuation: continuation)
                task.resume()
            }
        }
    }

    public func uploadTask(for request: URLRequest, fromFile url: URL) async throws(TransportError) -> (Data, HTTPURLResponse) {
        defer { onTaskCompleted() }
        return try await execute(for: request) { _ in
            let task = session.uploadTask(with: request, fromFile: url)
            onTaskCreated(task: task)
            return try await withCheckedThrowingContinuation { continuation in
                task.delegate = UploadTransferDelegate(continuation: continuation)
                task.resume()
            }
        }
    }

    // MARK: - Cancel
    @discardableResult
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
        progress.addChild(task.progress, withPendingUnitCount: 1)
    }

    private func onTaskCompleted() {
        task = nil
    }
}

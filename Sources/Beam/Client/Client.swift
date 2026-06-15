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

    // MARK: - WebSocket
    func webSocket(for request: URLRequest) async throws(ClientError) -> AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>
    func send(message: URLSessionWebSocketTask.Message) async throws(ClientError)
    func disconnect(code: URLSessionWebSocketTask.CloseCode, reason: Data?) async
    func ping() async throws(ClientError)
}

public actor Client: ClientProtocol, Identifiable {
    public nonisolated let id: String
    private let log: Logger
    private let session: any NetworkSession
    private let certificates: [Data]

    private var task: URLSessionTask?
    private var webSocketTask: URLSessionWebSocketTask?
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
        self.id = String(UUID().uuidString.prefix(4))

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

                log.response(rid: rid, status: status.rawValue, headers: httpResponse.allHeaderFields as? [String: String] ?? [:], value: value, start: start)

                guard status.type == .success else {
                    throw ClientError.http(status: status, body: value as? Data)
                }
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

// MARK: - WebSocket
extension Client {
    public func webSocket(for request: URLRequest) async throws(ClientError) -> AsyncThrowingStream<URLSessionWebSocketTask.Message, Error> {
        // Cancel existing WebSocket task if running
        if let existing = webSocketTask, existing.state == .running {
            existing.cancel(with: .normalClosure, reason: nil)
        }

        let wsTask = session.webSocketTask(with: request)
        self.webSocketTask = wsTask
        wsTask.resume()

        log.webSocketOpen(rid: id, request: request)

        let logRef = self.log
        let id = self.id
        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                while wsTask.state == .running {
                    do {
                        let message = try await wsTask.receive()
                        logRef.webSocketReceive(rid: id, message: message)
                        continuation.yield(message)
                    } catch {
                        if let clientError = ClientError.from(webSocketError: error) {
                            continuation.finish(throwing: clientError)
                        } else {
                            continuation.finish()
                        }
                        break
                    }
                }
                await self?.onWebSocketEnded()
            }
        }
    }

    public func send(message: URLSessionWebSocketTask.Message) async throws(ClientError) {
        guard let wsTask = webSocketTask, wsTask.state == .running else {
            throw .webSocket(.abnormalClosure, nil)
        }
        do {
            try await wsTask.send(message)
            log.webSocketSend(rid: id, message: message)
        } catch {
            throw .unknown(error)
        }
    }

    public func disconnect(code: URLSessionWebSocketTask.CloseCode, reason: Data?) async {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) }
        log.webSocketClose(rid: id, code: code.rawValue, reason: reasonStr)

        webSocketTask?.cancel(with: code, reason: reason)
        webSocketTask = nil
    }

    public func ping() async throws(ClientError) {
        guard let wsTask = webSocketTask, wsTask.state == .running else {
            throw .webSocket(.abnormalClosure, nil)
        }
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                wsTask.sendPing { error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume() }
                }
            }
            log.webSocketPing(rid: id)
        } catch {
            throw .unknown(error)
        }
    }

    // MARK: - Private

    private func onWebSocketEnded() {
        webSocketTask = nil
    }
}

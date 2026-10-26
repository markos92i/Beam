//
//  Client.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//

import Foundation

/// Transport of one call across all its attempts; validation, retries and decoding belong to `Call`.
actor Client {
    nonisolated let id: String
    /// A download starts at 5 %: URLSession counts the request as the first 5 % of a task.
    nonisolated let progress = Progress(totalUnitCount: 0)
    nonisolated let log: BeamLogger
    private let session: any SessionProtocol

    private var current: TaskTracker?
    private var resumeData: Data?
    private var runs: [UUID: @Sendable () -> Void] = [:]

    init(id: String = String(UUID().uuidString.prefix(4)), session: any SessionProtocol = Session(), logLevel: LogLevel? = nil) {
        self.id = id
        self.session = session
        self.log = BeamLogger(level: logLevel)
    }

    // MARK: - Run and cancel

    /// In a task of its own, so ``cancel()`` can cut whatever the call is doing.
    func run<T: Sendable, E: Error>(_ call: @escaping @Sendable () async throws(E) -> T) async throws(E) -> T {
        resumeData = nil
        let task = Task { () async -> Result<T, E> in
            do throws(E) { return .success(try await call()) } catch { return .failure(error) }
        }
        let key = UUID()
        runs[key] = { task.cancel() }
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        runs[key] = nil
        return try result.get()
    }

    /// Cancels the transfer before the runs: cancelling the runs first would lose its resume data.
    @discardableResult
    func cancel() async -> Data? {
        var produced: Data?
        switch current?.task {
        case let task as URLSessionUploadTask: produced = await task.cancelByProducingResumeData()
        case let task as URLSessionDownloadTask: produced = await task.cancelByProducingResumeData()
        case let task: task?.cancel()
        }
        for cancel in runs.values { cancel() }
        defer { resumeData = nil }
        return produced ?? resumeData
    }

    // MARK: - Attempt

    private func execute<T>(
        for request: URLRequest,
        operation: (TaskTracker) async throws(TransportError) -> sending (T, URLResponse)
    ) async throws(TransportError) -> (T, HTTPURLResponse) {
        let start = Date()
        let signpostState = log.beginRequest(id: id, method: request.httpMethod ?? "", path: request.url?.path() ?? "")
        log.log(.request(id: id, method: request.httpMethod ?? "", url: request.url!, headers: request.allHTTPHeaderFields, body: request.httpBody))

        let tracker = TaskTracker(progress: progress)
        current = tracker
        defer {
            tracker.finish()
            if current === tracker { current = nil }
        }

        let value: T
        let response: URLResponse
        do {
            (value, response) = try await operation(tracker)
        } catch {
            let error = resolve(error, of: tracker.task)
            keepResumeData(from: error)
            log.endRequest(signpostState, status: error.urlError?.code == .cancelled ? -2 : -1)
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            log.endRequest(signpostState, status: 0)
            throw .network(URLError(.badServerResponse))
        }

        // The stored file's name isn't decided yet: log the one the server suggests.
        let body: LogEvent.Body = if let data = value as? Data { .data(data) }
                                  else if let file = value as? URL { .file(name: httpResponse.suggestedFilename, bytes: try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) }
                                  else { .none }
        log.log(.response(id: id, status: httpResponse.statusCode, headers: httpResponse.allHeaderFields as? [String: String] ?? [:], body: body, start: start))
        log.endRequest(signpostState, status: httpResponse.statusCode)

        return (value, httpResponse)
    }

    private func keepResumeData(from error: TransportError) {
        guard case .network(let urlError) = error,
              let data = urlError.downloadTaskResumeData ?? urlError.uploadTaskResumeData else { return }
        resumeData = data
    }

    private func resolve(_ error: TransportError, of task: URLSessionTask?) -> TransportError {
        guard case .network(let urlError) = error else { return error }
        return .network(session.sessionDelegate.resolve(urlError, for: task))
    }

    // MARK: - Native async API

    private func native<T>(_ request: URLRequest, _ call: (TaskTracker) async throws(URLError) -> sending (T, URLResponse)) async throws(TransportError) -> (T, HTTPURLResponse) {
        try await execute(for: request) { tracker throws(TransportError) in
            do throws(URLError) { return try await call(tracker) } catch { throw .network(error) }
        }
    }

    func bytes(for request: URLRequest) async throws(TransportError) -> (URLSession.AsyncBytes, HTTPURLResponse) {
        try await native(request) { delegate throws(URLError) in try await session.bytes(for: request, delegate: delegate) }
    }

    func data(for request: URLRequest) async throws(TransportError) -> (Data, HTTPURLResponse) {
        try await native(request) { delegate throws(URLError) in try await session.data(for: request, delegate: delegate) }
    }

    func upload(for request: URLRequest, _ source: Payload) async throws(TransportError) -> (Data, HTTPURLResponse) {
        switch source {
        case .data(let data):
            return try await native(request) { delegate throws(URLError) in try await session.upload(for: request, from: data, delegate: delegate) }
        case .file(let url):
            try Self.checkReadable(url)
            return try await native(request) { delegate throws(URLError) in try await session.upload(for: request, fromFile: url, delegate: delegate) }
        case .resume:
            // URLSession has no async upload from resume data.
            return try await uploadTask(for: request, source)
        }
    }

    /// With resume data, URLSession uses the request stored in it; `request` is only logged.
    func download(for request: URLRequest, resumeFrom data: Data? = nil) async throws(TransportError) -> (URL, HTTPURLResponse) {
        try await native(request) { delegate throws(URLError) in
            if let data {
                try await session.download(resumeFrom: data, delegate: delegate)
            } else {
                try await session.download(for: request, delegate: delegate)
            }
        }
    }

    // MARK: - Delegate-driven tasks (background-compatible)

    func downloadTask(for request: URLRequest, resumeFrom data: Data? = nil) async throws(TransportError) -> (URL, HTTPURLResponse) {
        let task = data.map(session.downloadTask(withResumeData:)) ?? session.downloadTask(with: request)
        return try await execute(for: request) { tracker throws(TransportError) in
            tracker.track(task)
            return try await session.awaitDownload(for: task)
        }
    }

    func uploadTask(for request: URLRequest, _ source: Payload) async throws(TransportError) -> (Data, HTTPURLResponse) {
        let task: URLSessionUploadTask
        switch source {
        case .data(let data):
            task = session.uploadTask(with: request, from: data)
        case .file(let url):
            try Self.checkReadable(url)
            task = session.uploadTask(with: request, fromFile: url)
        case .resume(let data):
            task = session.uploadTask(withResumeData: data)
            // Unreadable resume data: the task would never start nor complete.
            guard task.progressIfAny != nil else {
                task.cancel()
                throw .network(.unreadableResumeData)
            }
        }
        return try await execute(for: request) { tracker throws(TransportError) in
            tracker.track(task)
            return try await session.awaitUpload(for: task)
        }
    }

    private static func checkReadable(_ url: URL) throws(TransportError) {
        do { try FileUtils.checkReadable(url) } catch { throw .file(error) }
    }

    // MARK: - Background transfers

    /// A background session uploads only from files: a body goes to a temporary file.
    func backgroundUpload(on session: Session<Background>, key: BackgroundTaskKey, request: URLRequest, _ payload: Payload) async throws(TransportError) -> (Data, HTTPURLResponse) {
        let temporary = FileUtils.temporaryLocation("upload")
        defer { FileUtils.discard(temporary) }
        return try await execute(for: request) { tracker throws(TransportError) in
            try await session.transfer(key, track: tracker.track) { () throws(FileError) -> URLSessionTask in
                switch payload {
                case .data(let data):
                    try FileUtils.write(data, to: temporary)
                    return session.urlSession.uploadTask(with: request, fromFile: temporary)
                case .file(let file):
                    try FileUtils.checkReadable(file)
                    return session.urlSession.uploadTask(with: request, fromFile: file)
                case .resume(let data):
                    return session.urlSession.uploadTask(withResumeData: data)
                }
            }.uploadResponse()
        }
    }

    func backgroundDownload(on session: Session<Background>, key: BackgroundTaskKey, request: URLRequest, resumeFrom data: Data? = nil) async throws(TransportError) -> (URL, HTTPURLResponse) {
        try await execute(for: request) { tracker throws(TransportError) in
            try await session.transfer(key, track: tracker.track) { () -> URLSessionTask in
                if let data { session.urlSession.downloadTask(withResumeData: data) } else { session.urlSession.downloadTask(with: request) }
            }.downloadResponse()
        }
    }
}

//
//  MockSession.swift
//  Beam
//
//  Actor-based mock implementation of `SessionProtocol` for testing.
//  Stubs responses at the URLSession level so the real Client logic (retry, error mapping, etc.) is exercised.
//

import Foundation
import Synchronization
@testable import Beam

actor MockSession: SessionProtocol {

    // MARK: - Types

    let sessionDelegate = SessionDelegate()

    // Handlers throw `URLError`, like a real session: anything else can't reach Beam.
    typealias DataHandler = @Sendable (URLRequest) async throws(URLError) -> (Data, URLResponse)
    typealias UploadResumeHandler = @Sendable (Data) async throws(URLError) -> (Data, URLResponse)
    typealias DownloadResumeHandler = @Sendable (Data) async throws(URLError) -> (URL, URLResponse)

    struct Stub<T: Sendable>: Sendable {
        let delay: Duration?
        let result: Result<T, URLError>

        init(_ result: Result<T, URLError>, delay: Duration? = nil) {
            self.result = result
            self.delay = delay
        }
    }

    // MARK: - State

    private(set) var recordedRequests: [URLRequest] = []
    /// The data each in-memory upload sent, in order.
    private(set) var recordedUploads: [Data] = []

    private let dataHandler: DataHandler?
    private let uploadResumeHandler: UploadResumeHandler?
    private let downloadResumeHandler: DownloadResumeHandler?
    private var dataStubs: [Stub<(Data, URLResponse)>] = []
    private var uploadStubs: [Stub<(Data, URLResponse)>] = []
    private var downloadStubs: [Stub<(URL, URLResponse)>] = []

    private var dataIndex = 0
    private var uploadIndex = 0
    private var downloadIndex = 0

    // MARK: - Init

    /// Closure-based init for simple tests. The handler is called for data/upload/download requests.
    init(_ handler: @escaping DataHandler, _ uploadResumeHandler: UploadResumeHandler? = nil, delay: TimeInterval? = nil) {
        if let delay {
            let delayedHandler: DataHandler = { (request) throws(URLError) in
                do { try await Task.sleep(for: .seconds(delay)) } catch { throw URLError(.cancelled) }
                return try await handler(request)
            }
            self.dataHandler = delayedHandler
        } else {
            self.dataHandler = handler
        }
        self.uploadResumeHandler = uploadResumeHandler
        self.downloadResumeHandler = nil
    }

    /// Init with only upload resume handler (for resume tests).
    init(uploadResume handler: @escaping UploadResumeHandler) {
        self.dataHandler = nil
        self.uploadResumeHandler = handler
        self.downloadResumeHandler = nil
    }

    /// Init with only download resume handler (for download resume tests).
    init(downloadResume handler: @escaping DownloadResumeHandler) {
        self.dataHandler = nil
        self.uploadResumeHandler = nil
        self.downloadResumeHandler = handler
    }

    /// Stub-based init for complex sequential scenarios.
    init() {
        self.dataHandler = nil
        self.uploadResumeHandler = nil
        self.downloadResumeHandler = nil
    }

    // MARK: - Stub Configuration

    func stubData(_ stubs: [Stub<(Data, URLResponse)>]) {
        dataStubs = stubs
        dataIndex = 0
    }

    func stubData(responses: [(Data, HTTPURLResponse)]) {
        dataStubs = responses.map { Stub(.success(($0.0, $0.1))) }
        dataIndex = 0
    }

    func stubData(error: URLError) {
        dataStubs = [Stub(.failure(error))]
        dataIndex = 0
    }

    func stubUpload(responses: [(Data, HTTPURLResponse)]) {
        uploadStubs = responses.map { Stub(.success(($0.0, $0.1))) }
        uploadIndex = 0
    }

    func stubDownload(responses: [(URL, HTTPURLResponse)]) {
        downloadStubs = responses.map { Stub(.success(($0.0, $0.1))) }
        downloadIndex = 0
    }

    func reset() {
        recordedRequests = []
        recordedUploads = []
        dataStubs = []
        uploadStubs = []
        downloadStubs = []
        dataIndex = 0
        uploadIndex = 0
        downloadIndex = 0
    }

    // MARK: - SessionProtocol Conformance

    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        recordedRequests.append(request)
        if let handler = dataHandler { return try await handler(request) }
        return try await resolveData()
    }

    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        recordedRequests.append(request)
        recordedUploads.append(data)
        if let handler = dataHandler { return try await handler(request) }
        return try await resolveUpload()
    }

    func upload(for request: URLRequest, fromFile url: URL, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        recordedRequests.append(request)
        if let handler = dataHandler { return try await handler(request) }
        return try await resolveUpload()
    }

    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) {
        recordedRequests.append(request)
        if let handler = dataHandler {
            let (data, response) = try await handler(request)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do { try data.write(to: tempURL) } catch { throw URLError(.cannotWriteToFile) }
            return (tempURL, response)
        }
        return try await resolveDownload()
    }

    func download(resumeFrom data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) {
        if let handler = downloadResumeHandler { return try await handler(data) }
        return try await resolveDownload()
    }

    nonisolated func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask {
        URLSession.shared.webSocketTask(with: request)
    }

    // MARK: - Delegate-driven tasks

    // The tasks are real but never resumed: `awaitUpload`/`awaitDownload` answer them
    // with the same handlers and stubs as the async API, and end with `.cancelled` as
    // soon as the task is cancelled (by the call's `cancel()` or the calling task).

    /// Resume data of the tasks created from it, by task identifier.
    private nonisolated let resumedTasks = Mutex<[Int: Data]>([:])

    private static let placeholder = URLRequest(url: URL(string: "https://mock.invalid/resume")!)

    nonisolated func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
        URLSession.shared.downloadTask(with: request)
    }

    nonisolated func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask {
        let task = URLSession.shared.downloadTask(with: Self.placeholder)
        resumedTasks.withLock { $0[task.taskIdentifier] = data }
        return task
    }

    nonisolated func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask {
        URLSession.shared.uploadTask(with: request, from: data)
    }

    nonisolated func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask {
        URLSession.shared.uploadTask(with: request, fromFile: url)
    }

    nonisolated func uploadTask(withResumeData data: Data) -> URLSessionUploadTask {
        let task = URLSession.shared.uploadTask(with: Self.placeholder, from: Data())
        resumedTasks.withLock { $0[task.taskIdentifier] = data }
        return task
    }

    func awaitUpload(for task: URLSessionUploadTask) async throws(TransportError) -> (Data, URLResponse) {
        let resume = resumedTasks.withLock { $0.removeValue(forKey: task.taskIdentifier) }
        let request = task.originalRequest ?? Self.placeholder
        if resume == nil { recordedRequests.append(request) }
        let dataHandler = self.dataHandler
        let uploadResumeHandler = self.uploadResumeHandler
        do throws(URLError) {
            return try await Self.answer(task) { () throws(URLError) in
                if let resume, let uploadResumeHandler { return try await uploadResumeHandler(resume) }
                if resume == nil, let dataHandler { return try await dataHandler(request) }
                return try await self.resolveUpload()
            }
        } catch {
            throw .network(error)
        }
    }

    func awaitDownload(for task: URLSessionDownloadTask) async throws(TransportError) -> (URL, URLResponse) {
        let resume = resumedTasks.withLock { $0.removeValue(forKey: task.taskIdentifier) }
        let request = task.originalRequest ?? Self.placeholder
        if resume == nil { recordedRequests.append(request) }
        let dataHandler = self.dataHandler
        let downloadResumeHandler = self.downloadResumeHandler
        do throws(URLError) {
            return try await Self.answer(task) { () throws(URLError) in
                if let resume, let downloadResumeHandler { return try await downloadResumeHandler(resume) }
                if resume == nil, let dataHandler {
                    let (data, response) = try await dataHandler(request)
                    return (try Self.temporaryFile(with: data), response)
                }
                return try await self.resolveDownload()
            }
        } catch {
            throw .network(error)
        }
    }

    /// Runs `body`, unless `task` is cancelled first.
    private static func answer<T: Sendable>(
        _ task: URLSessionTask,
        _ body: @escaping @Sendable () async throws(URLError) -> T
    ) async throws(URLError) -> T {
        let result = await withTaskGroup(of: Result<T, URLError>?.self) { group in
            group.addTask {
                do throws(URLError) { return .success(try await body()) } catch { return .failure(error) }
            }
            group.addTask {
                while task.state == .suspended || task.state == .running {
                    do { try await Task.sleep(for: .milliseconds(5)) } catch { return nil }
                }
                return .failure(URLError(.cancelled))
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failure(URLError(.cancelled))
        }
        return try result.get()
    }

    private static func temporaryFile(with data: Data) throws(URLError) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try data.write(to: url) } catch { throw URLError(.cannotWriteToFile) }
        return url
    }

    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URLSession.AsyncBytes, URLResponse) {
        recordedRequests.append(request)
        if let handler = dataHandler {
            let (data, response) = try await handler(request)
            // Serve bytes via a file URL (URLSession supports file:// for bytes)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".stream")
            do {
                try data.write(to: tempURL)
                let (bytes, _) = try await URLSession.shared.bytes(from: tempURL)
                return (bytes, response)
            } catch {
                throw URLError(bridging: error)
            }
        }
        throw URLError(.unknown)
    }

    // MARK: - Private

    private func resolveData() async throws(URLError) -> (Data, URLResponse) {
        guard !dataStubs.isEmpty else { throw URLError(.unknown) }
        let idx = min(dataIndex, dataStubs.count - 1)
        let stub = dataStubs[idx]
        dataIndex += 1
        if let delay = stub.delay { try? await Task.sleep(for: delay) }
        return try stub.result.get()
    }

    private func resolveUpload() async throws(URLError) -> (Data, URLResponse) {
        guard !uploadStubs.isEmpty else { throw URLError(.unknown) }
        let idx = min(uploadIndex, uploadStubs.count - 1)
        let stub = uploadStubs[idx]
        uploadIndex += 1
        if let delay = stub.delay { try? await Task.sleep(for: delay) }
        return try stub.result.get()
    }

    private func resolveDownload() async throws(URLError) -> (URL, URLResponse) {
        guard !downloadStubs.isEmpty else { throw URLError(.unknown) }
        let idx = min(downloadIndex, downloadStubs.count - 1)
        let stub = downloadStubs[idx]
        downloadIndex += 1
        if let delay = stub.delay { try? await Task.sleep(for: delay) }
        return try stub.result.get()
    }
}

// MARK: - Background tasks made by hand

extension Session where Kind == Background {
    /// A download task of this session described with `key`, as Beam makes them: for
    /// tests that drive the delegate callbacks themselves.
    func makeDownloadTask(_ request: URLRequest, key: BackgroundTaskKey) -> URLSessionDownloadTask {
        let task = urlSession.downloadTask(with: request)
        task.taskDescription = BackgroundTaskDescription(key).encoded
        return task
    }

    /// See ``makeDownloadTask(_:key:)``.
    func makeUploadTask(_ request: URLRequest, fromFile file: URL, key: BackgroundTaskKey) -> URLSessionUploadTask {
        let task = urlSession.uploadTask(with: request, fromFile: file)
        task.taskDescription = BackgroundTaskDescription(key).encoded
        return task
    }
}

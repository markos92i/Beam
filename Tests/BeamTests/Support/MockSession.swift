//
//  MockSession.swift
//  Beam
//
//  Actor-based mock implementation of `SessionProtocol` for testing.
//  Stubs responses at the URLSession level so the real Client logic (retry, error mapping, etc.) is exercised.
//

import Foundation
@testable import Beam

actor MockSession: SessionProtocol {

    // MARK: - Types

    typealias DataHandler = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias UploadResumeHandler = @Sendable (Data) async throws -> (Data, URLResponse)
    typealias DownloadResumeHandler = @Sendable (Data) async throws -> (URL, URLResponse)

    struct Stub<T: Sendable>: Sendable {
        let delay: Duration?
        let result: Result<T, Error>

        init(_ result: Result<T, Error>, delay: Duration? = nil) {
            self.result = result
            self.delay = delay
        }
    }

    // MARK: - State

    private(set) var recordedRequests: [URLRequest] = []

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
            let delayedHandler: DataHandler = { request in
                try await Task.sleep(for: .seconds(delay))
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

    func stubData(error: Error) {
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
        dataStubs = []
        uploadStubs = []
        downloadStubs = []
        dataIndex = 0
        uploadIndex = 0
        downloadIndex = 0
    }

    // MARK: - SessionProtocol Conformance

    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        if let handler = dataHandler { return try await handler(request) }
        return try await resolveData()
    }

    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        if let handler = dataHandler { return try await handler(request) }
        return try await resolveUpload()
    }

    func upload(for request: URLRequest, fromFile url: URL, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        if let handler = dataHandler { return try await handler(request) }
        return try await resolveUpload()
    }

    func upload(resumeFrom data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        if let handler = uploadResumeHandler { return try await handler(data) }
        return try await resolveUpload()
    }

    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (URL, URLResponse) {
        recordedRequests.append(request)
        if let handler = dataHandler {
            let (data, response) = try await handler(request)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: tempURL)
            return (tempURL, response)
        }
        return try await resolveDownload()
    }

    func download(resumeFrom data: Data, delegate: URLSessionTaskDelegate?) async throws -> (URL, URLResponse) {
        if let handler = downloadResumeHandler { return try await handler(data) }
        return try await resolveDownload()
    }

    nonisolated func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask {
        URLSession.shared.webSocketTask(with: request)
    }

    nonisolated func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
        URLSession.shared.downloadTask(with: request)
    }

    nonisolated func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask {
        URLSession.shared.downloadTask(withResumeData: data)
    }

    nonisolated func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask {
        URLSession.shared.uploadTask(with: request, from: data)
    }

    nonisolated func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask {
        URLSession.shared.uploadTask(with: request, fromFile: url)
    }

    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (URLSession.AsyncBytes, URLResponse) {
        recordedRequests.append(request)
        if let handler = dataHandler {
            let (data, response) = try await handler(request)
            // Serve bytes via a file URL (URLSession supports file:// for bytes)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".stream")
            try data.write(to: tempURL)
            let (bytes, _) = try await URLSession.shared.bytes(from: tempURL)
            return (bytes, response)
        }
        throw URLError(.unknown)
    }

    // MARK: - Private

    private func resolveData() async throws -> (Data, URLResponse) {
        guard !dataStubs.isEmpty else { throw URLError(.unknown) }
        let idx = min(dataIndex, dataStubs.count - 1)
        let stub = dataStubs[idx]
        dataIndex += 1
        if let delay = stub.delay { try? await Task.sleep(for: delay) }
        return try stub.result.get()
    }

    private func resolveUpload() async throws -> (Data, URLResponse) {
        guard !uploadStubs.isEmpty else { throw URLError(.unknown) }
        let idx = min(uploadIndex, uploadStubs.count - 1)
        let stub = uploadStubs[idx]
        uploadIndex += 1
        if let delay = stub.delay { try? await Task.sleep(for: delay) }
        return try stub.result.get()
    }

    private func resolveDownload() async throws -> (URL, URLResponse) {
        guard !downloadStubs.isEmpty else { throw URLError(.unknown) }
        let idx = min(downloadIndex, downloadStubs.count - 1)
        let stub = downloadStubs[idx]
        downloadIndex += 1
        if let delay = stub.delay { try? await Task.sleep(for: delay) }
        return try stub.result.get()
    }
}

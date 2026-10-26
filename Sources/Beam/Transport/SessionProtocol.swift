//
//  SessionProtocol.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 25/05/2026.
//

import Foundation

/// The URLSession surface Beam uses: its native async API and the delegate-driven tasks.
public protocol SessionProtocol: Sendable {
    var sessionDelegate: SessionDelegate { get }

    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URLSession.AsyncBytes, URLResponse)
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse)
    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse)
    func download(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse)
    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse)
    func upload(for: URLRequest, fromFile: URL, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse)

    // Delegate-driven tasks — background-compatible
    func downloadTask(with request: URLRequest) -> URLSessionDownloadTask
    func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask
    func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask
    func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask
    func uploadTask(withResumeData data: Data) -> URLSessionUploadTask

    /// Resumes a download task created by this session and waits for it to finish.
    func awaitDownload(for task: URLSessionDownloadTask) async throws(TransportError) -> (URL, URLResponse)

    /// Resumes an upload task created by this session and waits for it to finish.
    func awaitUpload(for task: URLSessionUploadTask) async throws(TransportError) -> (Data, URLResponse)

    func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask
}

// A task the session just created can't have finished: it always has a result to wait for.
extension SessionProtocol {
    public func awaitDownload(for task: URLSessionDownloadTask) async throws(TransportError) -> (URL, URLResponse) {
        guard let result = await sessionDelegate.attach(to: task) else { throw .network(URLError(.badServerResponse)) }
        return try result.downloadResponse()
    }

    public func awaitUpload(for task: URLSessionUploadTask) async throws(TransportError) -> (Data, URLResponse) {
        guard let result = await sessionDelegate.attach(to: task) else { throw .network(URLError(.badServerResponse)) }
        return try result.uploadResponse()
    }
}

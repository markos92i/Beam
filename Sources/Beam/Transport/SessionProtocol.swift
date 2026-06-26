//
//  SessionProtocol.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 25/05/2026.
//

import Foundation

public protocol SessionProtocol: Sendable {
    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (URLSession.AsyncBytes, URLResponse)
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (URL, URLResponse)
    func download(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws -> (URL, URLResponse)
    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
    func upload(for: URLRequest, fromFile: URL, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
    func upload(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)

    // Task-based — background-compatible
    func downloadTask(with request: URLRequest) -> URLSessionDownloadTask
    func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask
    func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask
    func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask
    func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask
}

extension URLSession: SessionProtocol {}

extension URLSession {
    public func upload(resumeFrom data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
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

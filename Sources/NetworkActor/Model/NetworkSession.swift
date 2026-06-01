//
//  NetworkSession.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 25/05/2026.
//

import Foundation

public protocol NetworkSession: Sendable {
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
    func upload(for: URLRequest, fromFile: URL, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
    func upload(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (URL, URLResponse)
    func download(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws -> (URL, URLResponse)
}

extension URLSession: NetworkSession {}

extension URLSession {
    public func upload(resumeFrom data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
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

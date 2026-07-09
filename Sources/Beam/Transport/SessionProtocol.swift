//
//  SessionProtocol.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 25/05/2026.
//

import Foundation

public protocol SessionProtocol: Sendable {
    var sessionDelegate: SessionDelegate { get }

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

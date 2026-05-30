//
//  MockSession.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 25/05/2026.
//

import Foundation
@testable import NetworkActor

actor MockSession: NetworkSession {
    var requestStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
    var resumeStub: (@Sendable (Data) async throws -> (Data, URLResponse))?
    var delay: TimeInterval?
    
    private let dummySession = URLSession(configuration: .default)
    private var activeTask: URLSessionTask?

    init(
        _ requestStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil,
        _ resumeStub: (@Sendable (Data) async throws -> (Data, URLResponse))? = nil,
        delay: TimeInterval? = nil
    ) {
        self.requestStub = requestStub
        self.resumeStub = resumeStub
        self.delay = delay
    }
    
    // MARK: - Helper para simular el ciclo del delegado
    private func triggerDelegateCallbacks(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws {
        guard let delegate = delegate else { return }
        
        let task = dummySession.dataTask(with: request)
        activeTask = task
        
        delegate.urlSession?(dummySession, didCreateTask: task)
    }
    
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        try await triggerDelegateCallbacks(for: request, delegate: delegate)
        try await applyDelayIfNeeded()
                
        guard let requestStub else { throw URLError(.badServerResponse) }
        
        return try await requestStub(request)
    }

    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        try await triggerDelegateCallbacks(for: request, delegate: delegate)
        try await applyDelayIfNeeded()
        
        guard let requestStub else { throw URLError(.badServerResponse) }
        
        return try await requestStub(request)
    }

    func upload(for request: URLRequest, fromFile: URL, delegate: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        try await triggerDelegateCallbacks(for: request, delegate: delegate)
        try await applyDelayIfNeeded()
        
        guard let requestStub else { throw URLError(.badServerResponse) }
        
        return try await requestStub(request)
    }
    
    func upload(resumeFrom data: Data, delegate: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        let dummyRequest = URLRequest(url: URL(string: "https://mock.resume")!)
        try await triggerDelegateCallbacks(for: dummyRequest, delegate: delegate)
        try await applyDelayIfNeeded()
        
        guard let resumeStub else { throw URLError(.badServerResponse) }
        
        return try await resumeStub(data)
    }

    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (URL, URLResponse) {
        try await triggerDelegateCallbacks(for: request, delegate: delegate)
        try await applyDelayIfNeeded()
        
        guard let requestStub else { throw URLError(.badServerResponse) }
        
        let (data, response) = try await requestStub(request)
        
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: temporaryURL)
        
        return (temporaryURL, response)
    }
    
    func download(resumeFrom data: Data, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        let dummyRequest = URLRequest(url: URL(string: "https://mock.resume")!)
        try await triggerDelegateCallbacks(for: dummyRequest, delegate: delegate)
        try await applyDelayIfNeeded()

        guard let resumeStub else { throw URLError(.badServerResponse) }
        
        let (data, response) = try await resumeStub(data)
        
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: temporaryURL)
        
        return (temporaryURL, response)
    }
    
    private func applyDelayIfNeeded() async throws {
        guard let delay else { return }

        try await Task.sleep(for: .seconds(delay))
        
        if activeTask?.state == .suspended { throw URLError(.cancelled) }
    }
}

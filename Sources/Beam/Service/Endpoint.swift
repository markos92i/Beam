//
//  Endpoint.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 21/5/24.
//

import Foundation

public protocol Endpoint: Identifiable, Sendable {
    associatedtype Operation
    @RequestBuilder var task: Operation { get }
}

// MARK: - RunEvent

public enum RunEvent<Success: Sendable, Failure: Sendable>: Sendable {
    case progress(Progress)
    case success(Success)
    case failure(APIError<Failure>)
}

// MARK: - DataTaskProtocol
extension Endpoint where Operation: DataTaskProtocol {
    public var id: String { task.service.id }
    public var progress: AsyncStream<Progress> { task.service.progress }

    public func call() async throws(APIError<Operation.Failure>) -> Operation.Success {
        try await task.service.data()
    }

    public func run() -> AsyncStream<RunEvent<Operation.Success, Operation.Failure>> {
        task.service.run { try await $0.data() }
    }

    @discardableResult
    public func cancel() async -> Data? {
        await task.service.cancel()
    }
}

// MARK: - UploadTaskProtocol
extension Endpoint where Operation: UploadTaskProtocol {
    public var id: String { task.service.id }
    public var progress: AsyncStream<Progress> { task.service.progress }

    public func call() async throws(APIError<Operation.Failure>) -> Operation.Success {
        try await task.service.upload()
    }

    public func call(url: URL) async throws(APIError<Operation.Failure>) -> Operation.Success {
        try await task.service.upload(url: url)
    }

    public func call(resumeFrom data: Data) async throws(APIError<Operation.Failure>) -> Operation.Success {
        try await task.service.upload(resumeFrom: data)
    }

    public func run() -> AsyncStream<RunEvent<Operation.Success, Operation.Failure>> {
        task.service.run { try await $0.upload() }
    }

    public func run(url: URL) -> AsyncStream<RunEvent<Operation.Success, Operation.Failure>> {
        task.service.run { try await $0.upload(url: url) }
    }

    public func run(resumeFrom data: Data) -> AsyncStream<RunEvent<Operation.Success, Operation.Failure>> {
        task.service.run { try await $0.upload(resumeFrom: data) }
    }

    @discardableResult
    public func cancel() async -> Data? {
        await task.service.cancel()
    }
}

// MARK: - DownloadTaskProtocol
extension Endpoint where Operation: DownloadTaskProtocol {
    public var id: String { task.service.id }
    public var progress: AsyncStream<Progress> { task.service.progress }

    public func call() async throws(APIError<Operation.Failure>) -> URL {
        try await task.service.download()
    }

    public func call(resumeFrom data: Data) async throws(APIError<Operation.Failure>) -> URL {
        try await task.service.download(resumeFrom: data)
    }

    public func run() -> AsyncStream<RunEvent<URL, Operation.Failure>> {
        task.service.run { try await $0.download() }
    }

    public func run(resumeFrom data: Data) -> AsyncStream<RunEvent<URL, Operation.Failure>> {
        task.service.run { try await $0.download(resumeFrom: data) }
    }

    @discardableResult
    public func cancel() async -> Data? {
        await task.service.cancel()
    }
}

// MARK: - StreamTaskProtocol
extension Endpoint where Operation: StreamTaskProtocol {
    public var id: String { task.service.id }
    public var progress: AsyncStream<Progress> { task.service.progress }

    public func connect() async throws(APIError<Operation.Failure>) -> AsyncThrowingStream<StreamEvent<Operation.Success, Operation.Failure>, Error> {
        try await task.service.stream()
    }

    public func send(_ value: Operation.Success) async throws(APIError<Operation.Failure>) {
        try await task.service.send(value)
    }

    public func send(data: Data) async throws(APIError<Operation.Failure>) {
        try await task.service.send(data: data)
    }

    public func send(text: String) async throws(APIError<Operation.Failure>) {
        try await task.service.send(text: text)
    }

    public func disconnect(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) async {
        await task.service.disconnect(code: code, reason: reason)
    }

    public func ping() async throws(APIError<Operation.Failure>) {
        try await task.service.ping()
    }
}

//
//  Endpoint.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 21/5/24.
//

import Foundation

public protocol Endpoint: Identifiable, Sendable {
    associatedtype Operation
    @DSLBuilder var task: Operation { get }
}

// MARK: - DataTaskProtocol
extension Endpoint where Operation: DataTaskProtocol {
    public var id: String { task.service.id }
    public var progress: AsyncStream<Progress> { task.service.progress }

    public func call() async throws(ServiceError<Operation.Failure>) -> Operation.Success {
        try await task.service.data()
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

    public func call() async throws(ServiceError<Operation.Failure>) -> Operation.Success {
        try await task.service.upload()
    }

    public func call(url: URL) async throws(ServiceError<Operation.Failure>) -> Operation.Success {
        try await task.service.upload(url: url)
    }

    public func call(resumeFrom data: Data) async throws(ServiceError<Operation.Failure>) -> Operation.Success {
        try await task.service.upload(resumeFrom: data)
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

    public func call() async throws(ServiceError<Operation.Failure>) -> URL {
        try await task.service.download()
    }

    public func call(resumeFrom data: Data) async throws(ServiceError<Operation.Failure>) -> URL {
        try await task.service.download(resumeFrom: data)
    }

    @discardableResult
    public func cancel() async -> Data? {
        await task.service.cancel()
    }
}

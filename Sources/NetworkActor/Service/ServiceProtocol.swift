//
//  Endpoint.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 21/5/24.
//

import Foundation

public protocol Endpoint: Identifiable, Sendable {
    associatedtype Success: Sendable
    associatedtype Failure: Sendable
    
    var id: String { get }
    @DSLBuilder
    var service: Service<Success, Failure> { get }
    var progress: AsyncStream<Progress> { get }
    
    func data() async throws(ServiceError<Failure>) -> Success
    func upload() async throws(ServiceError<Failure>) -> Success
    func upload(url: URL) async throws(ServiceError<Failure>) -> Success
    func upload(resumeFrom data: Data) async throws(ServiceError<Failure>) -> Success
    func download() async throws(ServiceError<Failure>) -> URL
    func download(resumeFrom data: Data) async throws(ServiceError<Failure>) -> URL
    func cancel() async -> Data?
}

extension Endpoint {
    public var id: String { service.id }
    public var progress: AsyncStream<Progress> { service.progress }
            
    public func data() async throws(ServiceError<Failure>) -> Success {
        try await service.data()
    }
    
    public func upload() async throws(ServiceError<Failure>) -> Success {
        try await service.upload()
    }
    
    public func upload(url: URL) async throws(ServiceError<Failure>) -> Success {
        try await service.upload(url: url)
    }
    
    public func upload(resumeFrom data: Data) async throws(ServiceError<Failure>) -> Success {
        try await service.upload(resumeFrom: data)
    }
    
    public func download() async throws(ServiceError<Failure>) -> URL {
        try await service.download()
    }
    
    public func download(resumeFrom data: Data) async throws(ServiceError<Failure>) -> URL {
        try await service.download(resumeFrom: data)
    }
    
    @discardableResult
    public func cancel() async -> Data? {
        await service.cancel()
    }
}

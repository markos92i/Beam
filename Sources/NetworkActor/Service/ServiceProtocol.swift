//
//  ServiceProtocol.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 21/5/24.
//

import SwiftUI

public protocol ServiceProtocol: Identifiable, Sendable {
    associatedtype Success: Sendable
    associatedtype Failure: Sendable
    
    var id: String { get }
    var service: ServiceManager<Success, Failure> { get }
    var progress: AsyncStream<Progress> { get }
    
    func request() async throws(ServiceError<Failure>) -> Success
    func upload() async throws(ServiceError<Failure>) -> Success
    func download() async throws(ServiceError<Failure>) -> URL
    func cancel() async
}

extension ServiceProtocol {
    public var id: String { service.id }
    public var progress: AsyncStream<Progress> { service.network.progress }
    
    public func request() async throws(ServiceError<Failure>) -> Success {
        try await service.request()
    }
    
    public func upload() async throws(ServiceError<Failure>) -> Success {
        try await service.upload()
    }
    
    public func download() async throws(ServiceError<Failure>) -> URL {
        try await service.download()
    }

    public func cancel() async {
        await service.cancel()
    }
}

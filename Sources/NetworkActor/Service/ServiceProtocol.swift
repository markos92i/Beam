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
    func request() async -> Result<Success, ServiceError<Failure>>
    func stream() async throws(ServiceError<Failure>) -> AsyncThrowingStream<String, ServiceError<Failure>>
    func stream() async -> Result<AsyncThrowingStream<String, ServiceError<Failure>>, ServiceError<Failure>>
    func cancel() async
}

extension ServiceProtocol {
    public var id: String { service.network.uuid }
    public var progress: AsyncStream<Progress> { service.network.progress }
    
    public func request() async throws(ServiceError<Failure>) -> Success {
        try await service.request()
    }
    
    public func request() async -> Result<Success, ServiceError<Failure>> {
        do {
            return .success(try await request())
        } catch {
            return .failure(error)
        }
    }
    
    public func stream() async throws(ServiceError<Failure>) -> AsyncThrowingStream<String, ServiceError<Failure>> {
        try await service.stream()
    }
    
    public func stream() async -> Result<AsyncThrowingStream<String, ServiceError<Failure>>, ServiceError<Failure>> {
        do {
            return .success(try await stream())
        } catch {
            return .failure(error)
        }
    }
    
    public func cancel() async {
        await service.cancel()
    }
}

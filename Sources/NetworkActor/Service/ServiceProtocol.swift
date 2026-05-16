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
    var progressAsync: Progress { get async }
    
    func request() async throws(ServiceError<Failure>) -> Success
    func request() async -> Result<Success, ServiceError<Failure>>
    func cancel() async
}

extension ServiceProtocol {
    public var id: String { service.network.uuid }
    public var progress: Progress { get async { await service.network.current } }
    
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
        
    public func cancel() async {
        await service.cancel()
    }
}

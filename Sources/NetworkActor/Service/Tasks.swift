//
//  Tasks.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 11/06/2026.
//

import Foundation

// MARK: - Task Protocols
public protocol DataTaskProtocol: Sendable {
    associatedtype Success: Sendable
    associatedtype Failure: Sendable
    var service: Service<Success, Failure> { get }
}

public protocol UploadTaskProtocol: Sendable {
    associatedtype Success: Sendable
    associatedtype Failure: Sendable
    var service: Service<Success, Failure> { get }
}

public protocol DownloadTaskProtocol: Sendable {
    associatedtype Failure: Sendable
    var service: Service<URL, Failure> { get }
}

// MARK: - Task Types
public struct DataTask<Success: Sendable, Failure: Sendable>: DataTaskProtocol, Sendable {
    public let service: Service<Success, Failure>
}

public struct UploadTask<Success: Sendable, Failure: Sendable>: UploadTaskProtocol, Sendable {
    public let service: Service<Success, Failure>
}

public struct DownloadTask<Failure: Sendable>: DownloadTaskProtocol, Sendable {
    public let service: Service<URL, Failure>
}

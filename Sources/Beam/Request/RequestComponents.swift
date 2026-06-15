//
//  RequestComponents.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 01/06/2026.
//

import Foundation

// MARK: - Core Protocol

public protocol RequestComponent: Sendable {
    func apply(to builder: inout RequestBuilderState)
}

// MARK: - Component Structs

public enum DSL {
    public struct Method: RequestComponent {
        let method: HTTPMethod
        let host: String
        let path: String
        public func apply(to builder: inout RequestBuilderState) {
            builder.method = method
            builder.host = host
            builder.path = path
        }
    }

    public struct Header: RequestComponent {
        private let closure: @Sendable (inout [String: String]) -> Void
        public init(_ key: String, value: String) { closure = { $0[key] = value } }
        public init(_ dictionary: [String: String]) { closure = { $0.merge(dictionary) { _, new in new } } }
        public func apply(to builder: inout RequestBuilderState) { closure(&builder.headers) }
    }

    public struct Query: RequestComponent {
        private let closure: @Sendable (inout [URLQueryItem]) -> Void
        public init(_ name: String, value: String) { closure = { $0.append(.init(name: name, value: value)) } }
        public init(_ item: URLQueryItem) { closure = { $0.append(item) } }
        public init(_ items: [URLQueryItem]) { closure = { $0.append(contentsOf: items) } }
        public func apply(to builder: inout RequestBuilderState) { closure(&builder.params) }
    }

    public struct Body: RequestComponent {
        let body: HTTPBody
        public func apply(to builder: inout RequestBuilderState) { builder.body = body }
    }

    public struct Timeout: RequestComponent {
        let interval: TimeInterval
        public func apply(to builder: inout RequestBuilderState) { builder.config.timeout = interval }
    }

    public struct Use: RequestComponent {
        let client: any ClientProtocol
        public func apply(to builder: inout RequestBuilderState) { builder.client = client }
    }

    public struct Auth: RequestComponent {
        let auth: any AuthProtocol
        public func apply(to builder: inout RequestBuilderState) { builder.auth = auth }
    }

    public struct Crash: RequestComponent {
        let crash: any CrashProtocol
        public func apply(to builder: inout RequestBuilderState) { builder.crash = crash }
    }

    public struct Mapper: RequestComponent {
        let serializer: SerializerProtocol
        public func apply(to builder: inout RequestBuilderState) { builder.serializer = serializer }
    }

    public struct Config: RequestComponent {
        let config: RequestConfig
        public func apply(to builder: inout RequestBuilderState) { builder.config = config }
    }

    public struct Cache: RequestComponent {
        let file: String
        public func apply(to builder: inout RequestBuilderState) { builder.cacheFile = file }
    }

    public struct Retry: RequestComponent {
        let policy: RetryPolicy
        public func apply(to builder: inout RequestBuilderState) { builder.config.retry = policy }
    }

    public struct PingInterval: RequestComponent {
        let interval: TimeInterval
        public func apply(to builder: inout RequestBuilderState) {
            guard interval > 0, interval <= 300 else { return }
            builder.config.pingInterval = interval
        }
    }
}

// MARK: - Builder Functions

public func Connect(_ host: String, _ path: String) -> DSL.Method { .init(method: .connect, host: host, path: path) }
public func Get(_ host: String, _ path: String) -> DSL.Method { .init(method: .get, host: host, path: path) }
public func Post(_ host: String, _ path: String) -> DSL.Method { .init(method: .post, host: host, path: path) }
public func Put(_ host: String, _ path: String) -> DSL.Method { .init(method: .put, host: host, path: path) }
public func Delete(_ host: String, _ path: String) -> DSL.Method { .init(method: .delete, host: host, path: path) }
public func Patch(_ host: String, _ path: String) -> DSL.Method { .init(method: .patch, host: host, path: path) }
public func Head(_ host: String, _ path: String) -> DSL.Method { .init(method: .head, host: host, path: path) }
public func Options(_ host: String, _ path: String) -> DSL.Method { .init(method: .options, host: host, path: path) }
public func Trace(_ host: String, _ path: String) -> DSL.Method { .init(method: .trace, host: host, path: path) }

public func Header(_ key: String, value: String) -> DSL.Header { .init(key, value: value) }
public func Header(_ dictionary: [String: String]) -> DSL.Header { .init(dictionary) }

public func Query(_ name: String, value: String) -> DSL.Query { .init(name, value: value) }
public func Query(_ item: URLQueryItem) -> DSL.Query { .init(item) }
public func Query(_ items: [URLQueryItem]) -> DSL.Query { .init(items) }

public func Body(_ body: HTTPBody) -> DSL.Body { .init(body: body) }
public func Timeout(_ interval: TimeInterval) -> DSL.Timeout { .init(interval: interval) }
public func Use(_ client: any ClientProtocol) -> DSL.Use { .init(client: client) }
public func Auth(_ auth: any AuthProtocol) -> DSL.Auth { .init(auth: auth) }
public func Crash(_ crash: any CrashProtocol) -> DSL.Crash { .init(crash: crash) }
public func Mapper(_ serializer: SerializerProtocol) -> DSL.Mapper { .init(serializer: serializer) }
public func Config(_ config: RequestConfig) -> DSL.Config { .init(config: config) }
public func Cache(_ file: String) -> DSL.Cache { .init(file: file) }
public func Retry(_ policy: RetryPolicy) -> DSL.Retry { .init(policy: policy) }
public func PingInterval(_ interval: TimeInterval) -> DSL.PingInterval { .init(interval: interval) }

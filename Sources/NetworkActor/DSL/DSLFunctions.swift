//
//  DSLFunctions.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 01/06/2026.
//

import Foundation

// MARK: Methods
public func Connect(_ host: String, _ path: String) -> DSL.Method { .init(method: .connect, host: host, path: path) }
public func Get(_ host: String, _ path: String) -> DSL.Method { .init(method: .get, host: host, path: path) }
public func Post(_ host: String, _ path: String) -> DSL.Method { .init(method: .post, host: host, path: path) }
public func Put(_ host: String, _ path: String) -> DSL.Method { .init(method: .put, host: host, path: path) }
public func Delete(_ host: String, _ path: String) -> DSL.Method { .init(method: .delete, host: host, path: path) }
public func Patch(_ host: String, _ path: String) -> DSL.Method { .init(method: .patch, host: host, path: path) }
public func Head(_ host: String, _ path: String) -> DSL.Method { .init(method: .head, host: host, path: path) }
public func Options(_ host: String, _ path: String) -> DSL.Method { .init(method: .options, host: host, path: path) }
public func Trace(_ host: String, _ path: String) -> DSL.Method { .init(method: .trace, host: host, path: path) }

// MARK: Header
public func Header(_ key: String, value: String) -> DSL.Header { .init(key, value: value) }
public func Header(_ dictionary: [String: String]) -> DSL.Header { .init(dictionary) }

// MARK: Query
public func Query(_ name: String, value: String) -> DSL.Query { .init(name, value: value) }
public func Query(_ item: URLQueryItem) -> DSL.Query { .init(item) }
public func Query(_ items: [URLQueryItem]) -> DSL.Query { .init(items) }

// MARK: Body
public func Body(_ body: HTTPBody) -> DSL.Body { .init(body: body) }

// MARK: Task Timeout
public func Timeout(_ interval: TimeInterval) -> DSL.Timeout { .init(interval: interval) }

// MARK: Configuration
public func Use(_ client: any ClientProtocol) -> DSL.Use { .init(client: client) }
public func Auth(_ auth: any AuthProtocol) -> DSL.Auth { .init(auth: auth) }
public func Crash(_ crash: any CrashProtocol) -> DSL.Crash { .init(crash: crash) }
public func Mapper(_ serializer: Serializer) -> DSL.Mapper { .init(serializer: serializer) }
public func Config(_ config: ServiceConfig) -> DSL.Config { .init(config: config) }

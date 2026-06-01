//
//  DSL.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 01/06/2026.
//

import Foundation

// MARK: - Structs
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
        private let closure: (inout [String: String]) -> Void
        public init(_ key: String, value: String) { closure = { $0[key] = value } }
        public init(_ dictionary: [String: String]) { closure = { $0.merge(dictionary) { _, new in new } } }
        public func apply(to builder: inout RequestBuilderState) { closure(&builder.headers) }
    }

    public struct Query: RequestComponent {
        private let closure: (inout [URLQueryItem]) -> Void
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
        public func apply(to builder: inout RequestBuilderState) { builder.timeout = interval }
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
        let config: ServiceConfig
        public func apply(to builder: inout RequestBuilderState) { builder.config = config }
    }
}

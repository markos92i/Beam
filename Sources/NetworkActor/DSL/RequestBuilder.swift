//
//  RequestBuilder.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 31/5/26.
//

import Foundation

// MARK: - Core Protocol
public protocol RequestComponent {
    func apply(to builder: inout RequestBuilderState)
}

// MARK: - Structs
public enum NetworkDSL {
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
        let item: URLQueryItem
        public func apply(to builder: inout RequestBuilderState) { builder.params.append(item) }
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
        public func apply(to builder: inout RequestBuilderState) { builder.network = client }
    }

    public struct Auth: RequestComponent {
        let auth: any AuthProtocol
        public func apply(to builder: inout RequestBuilderState) { builder.auth = auth }
    }

    public struct Crash: RequestComponent {
        let crash: any CrashProtocol
        public func apply(to builder: inout RequestBuilderState) { builder.crash = crash }
    }

    public struct WithSerializer: RequestComponent {
        let serializer: Serializer
        public func apply(to builder: inout RequestBuilderState) { builder.serializer = serializer }
    }

    public struct Config: RequestComponent {
        let config: ServiceConfig
        public func apply(to builder: inout RequestBuilderState) { builder.config = config }
    }
}


// MARK: - Global Functions
public func Connect(_ host: String, _ path: String) -> NetworkDSL.Method { .init(method: .connect, host: host, path: path) }
public func Get(_ host: String, _ path: String) -> NetworkDSL.Method { .init(method: .get, host: host, path: path) }
public func Post(_ host: String, _ path: String) -> NetworkDSL.Method { .init(method: .post, host: host, path: path) }
public func Put(_ host: String, _ path: String) -> NetworkDSL.Method { .init(method: .put, host: host, path: path) }
public func Delete(_ host: String, _ path: String) -> NetworkDSL.Method { .init(method: .delete, host: host, path: path) }
public func Patch(_ host: String, _ path: String) -> NetworkDSL.Method { .init(method: .patch, host: host, path: path) }
public func Head(_ host: String, _ path: String) -> NetworkDSL.Method { .init(method: .head, host: host, path: path) }
public func Options(_ host: String, _ path: String) -> NetworkDSL.Method { .init(method: .options, host: host, path: path) }
public func Trace(_ host: String, _ path: String) -> NetworkDSL.Method { .init(method: .trace, host: host, path: path) }
public func Header(_ key: String, value: String) -> NetworkDSL.Header { .init(key, value: value) }
public func Header(_ dictionary: [String: String]) -> NetworkDSL.Header { .init(dictionary) }
public func Query(_ name: String, value: String?) -> NetworkDSL.Query { .init(item: URLQueryItem(name: name, value: value)) }
public func Body(_ body: HTTPBody) -> NetworkDSL.Body { .init(body: body) }
public func Timeout(_ interval: TimeInterval) -> NetworkDSL.Timeout { .init(interval: interval) }

public func Use(_ client: any ClientProtocol) -> NetworkDSL.Use { .init(client: client) }
public func Auth(_ auth: any AuthProtocol) -> NetworkDSL.Auth { .init(auth: auth) }
public func Crash(_ crash: any CrashProtocol) -> NetworkDSL.Crash { .init(crash: crash) }
public func WithSerializer(_ serializer: Serializer) -> NetworkDSL.WithSerializer { .init(serializer: serializer) }
public func Config(_ config: ServiceConfig) -> NetworkDSL.Config { .init(config: config) }


// MARK: - State, Builder & Container
public struct RequestBuilderState {
    var network: any ClientProtocol = NetworkClient(session: URLSession.shared)
    var auth: (any AuthProtocol)? = nil
    var crash: (any CrashProtocol)? = nil
    var serializer: Serializer = .init()
    var config: ServiceConfig = .standard
    
    var method: HTTPMethod = .get
    var host: String = ""
    var path: String = ""
    var params: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: HTTPBody? = nil
    var timeout: TimeInterval = 60
}

public struct ValidatedRequest {
    let method: NetworkDSL.Method
    let modifiers: [RequestComponent]
}

@resultBuilder
public struct DSLBuilder {
    public static func buildBlock(_ method: NetworkDSL.Method, _ modifiers: RequestComponent...) -> ValidatedRequest {
        ValidatedRequest(method: method, modifiers: modifiers)
    }
    public static func buildOptional(_ component: [RequestComponent]?) -> [RequestComponent] { component ?? [] }
}

public struct RequestBuilder<Success: Sendable, Failure: Sendable> {
    private let validatedRequest: ValidatedRequest
    
    public init(@DSLBuilder _ builder: () -> ValidatedRequest) {
        self.validatedRequest = builder()
    }
    
    public func build() -> Service<Success, Failure> {
        var state = RequestBuilderState()
        
        validatedRequest.method.apply(to: &state)
        
        validatedRequest.modifiers.forEach { $0.apply(to: &state) }
        
        let payload = ServicePayload(
            method: state.method,
            host: state.host,
            path: state.path,
            params: state.params,
            headers: state.headers,
            body: state.body,
            timeout: state.timeout
        )
        
        return Service<Success, Failure>(
            network: state.network,
            auth: state.auth,
            crash: state.crash,
            serializer: state.serializer,
            config: state.config,
            api: payload
        )
    }
}

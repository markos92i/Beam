//
//  APIMacroSupport.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

// MARK: - Main Macro

/// Transforms a protocol into a fully-functional API client struct.
///
/// Parameter roles are detected by **external label convention**:
/// - `body` (external label) → JSON-encoded request body
/// - `query` (external label) → named query parameter (key = internal name)
/// - `header` (external label) → dynamic HTTP header (key = internal name)
/// - `url` (external label) + type `URL` → absolute URL override (bypasses host + base + path)
/// - Type `[URLQueryItem]` → query items array passed directly
/// - Matches `{name}` in path → path parameter (string-interpolated)
///
/// ## Escaping Conventions
///
/// All role detection is driven by the **external label**. Use Swift's dual naming
/// (external/internal) to escape collisions with domain names:
///
/// ```swift
/// // "body" as HTTP body:
/// func create(body request: CreateRequest) async throws(APIError<E>) -> Item
///
/// // Domain field named "body" — escape with a different external label:
/// func update(_ body: BodyModel) async throws(APIError<E>) -> Item
///
/// // Absolute URL override:
/// func download(url: URL) async throws(APIError<E>) -> URL
///
/// // A URL param that is NOT an override — escape:
/// func process(target url: URL) async throws(APIError<E>) -> Result
/// ```
///
/// ## Absolute URL
///
/// When a parameter has external label `url` and type `URL`, the generated code
/// uses it as the full request target, ignoring the configured `host` and `base`.
/// Auth, headers, interceptors, and retry still apply. This is analogous to
/// Retrofit's `@Url` annotation.
///
/// > Note: For upload tasks (`task: .upload`), `url: URL` retains its existing
/// > meaning of "local file source" and does NOT trigger the absolute URL override.
@attached(peer, names: suffixed(Client), suffixed(Mock))
public macro API(
    host: String,
    base: String = "",
    headers: [String: String] = [:],
    session: Any? = nil,
    auth: Any? = nil,
    crash: Any? = nil,
    mapper: Any? = nil,
    mock: Bool = false
) = #externalMacro(module: "BeamMacros", type: "APIMacro")

// MARK: - HTTP Method Markers

/// GET endpoint. Path params use `{name}` syntax.
@attached(peer)
public macro Get(_ path: String = "", task: _TaskKind = .data, headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "GetMacro")

/// POST endpoint.
@attached(peer)
public macro Post(_ path: String = "", task: _TaskKind = .data, headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "PostMacro")

/// PUT endpoint.
@attached(peer)
public macro Put(_ path: String = "", task: _TaskKind = .data, headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "PutMacro")

/// DELETE endpoint.
@attached(peer)
public macro Delete(_ path: String = "", task: _TaskKind = .data, headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "DeleteMacro")

/// PATCH endpoint.
@attached(peer)
public macro Patch(_ path: String = "", task: _TaskKind = .data, headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "PatchMacro")

/// HEAD endpoint.
@attached(peer)
public macro Head(_ path: String = "", task: _TaskKind = .data, headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "HeadMacro")

/// OPTIONS endpoint.
@attached(peer)
public macro Options(_ path: String = "", task: _TaskKind = .data, headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "OptionsMacro")

/// CONNECT endpoint.
@attached(peer)
public macro Connect(_ path: String = "", task: _TaskKind = .data, headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "ConnectMacro")

/// TRACE endpoint.
@attached(peer)
public macro Trace(_ path: String = "", task: _TaskKind = .data, headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "TraceMacro")

/// WebSocket endpoint. Opens a persistent bidirectional connection (GET + upgrade).
@attached(peer)
public macro Socket(_ path: String = "", headers: [String: String] = [:], timeout: TimeInterval? = nil, retry: RetryPolicy? = nil, auth: AuthPolicy? = nil, mapper: (any MapperProtocol)? = nil) = #externalMacro(module: "BeamMacros", type: "SocketMacro")

// MARK: - Supporting Types

/// Task kind marker for route macros.
///
/// - Important: Internal to the `@API` macro system. Do not use directly.
public enum _TaskKind: Sendable {
    case data
    case upload
    case download
    case bytes
}

// MARK: - Runtime Configuration Container

/// Shared configuration container generated by `@API`.
///
/// - Important: Internal to the macro system. Do not instantiate manually.
public struct _APIConfiguration: Sendable {
    public let host: String
    public let base: String
    public let headers: [String: String]
    public let session: any SessionProtocol
    public let auth: (any AuthProtocol)?
    public let crash: (any CrashProtocol)?
    public let mapper: any MapperProtocol
    public let config: RequestConfig
    public let interceptors: [any RequestInterceptor]
    public let logLevel: LogLevel?

    public init(
        host: String,
        base: String,
        headers: [String: String] = [:],
        session: any SessionProtocol = URLSession.shared,
        auth: (any AuthProtocol)? = nil,
        crash: (any CrashProtocol)? = nil,
        mapper: any MapperProtocol = Mapper(),
        config: RequestConfig = .standard,
        interceptors: [any RequestInterceptor] = [],
        logLevel: LogLevel? = nil
    ) {
        self.host = host
        self.base = base
        self.headers = headers
        self.session = session
        self.auth = auth
        self.crash = crash
        self.mapper = mapper
        self.config = config
        self.interceptors = interceptors
        self.logLevel = logLevel
    }
}

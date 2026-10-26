//
//  APIMacroSupport.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

// MARK: - Main Macro

/// Generates `<Protocol>Client` from the protocol's routes. Parameter roles, by external label:
/// - `body`: request body (`Data` as is, `String` as text, ``HTTPBody``, else JSON).
/// - `query name`: query item keyed by `name`; arrays repeat the key.
/// - `header name`: header keyed by `name`.
/// - `url`: absolute URL override; in `task: .upload`, the local file to upload.
/// - `resumeFrom`: resume data of an interrupted upload or download.
/// - `{name}` placeholder label: fills it; unmatched placeholders read ``APIValues``.
/// - Unlabeled: `[URLQueryItem]` only.
@attached(peer, names: suffixed(Client))
public macro API(
    host: String,
    base: String = "",
    headers: [String: String] = [:],
    session: (any SessionProtocol)? = nil,
    background: Session<Background>? = nil,
    auth: (any AuthProtocol)? = nil,
    monitors: [any Monitor] = [],
    config: RequestConfig = .standard,
    socket: SocketConfig = .standard,
    interceptors: [any Interceptor] = [],
    logLevel: LogLevel? = nil
) = #externalMacro(module: "BeamMacros", type: "APIMacro")

// MARK: - HTTP Method Markers

// `@API` never reads these defaults; `retry` is non-optional so `.none` means `RetryPolicy.none`.

/// GET endpoint.
@attached(peer)
public macro Get(_ path: String = "", task: _TaskKind = .data, query: [String: String] = [:], headers: [String: String] = [:], timeout: Duration? = nil, retry: RetryPolicy = .standard, auth: AuthPolicy? = nil, json: JSONCoding? = nil) = #externalMacro(module: "BeamMacros", type: "GetMacro")

/// POST endpoint.
@attached(peer)
public macro Post(_ path: String = "", task: _TaskKind = .data, query: [String: String] = [:], headers: [String: String] = [:], timeout: Duration? = nil, retry: RetryPolicy = .standard, auth: AuthPolicy? = nil, json: JSONCoding? = nil) = #externalMacro(module: "BeamMacros", type: "PostMacro")

/// PUT endpoint.
@attached(peer)
public macro Put(_ path: String = "", task: _TaskKind = .data, query: [String: String] = [:], headers: [String: String] = [:], timeout: Duration? = nil, retry: RetryPolicy = .standard, auth: AuthPolicy? = nil, json: JSONCoding? = nil) = #externalMacro(module: "BeamMacros", type: "PutMacro")

/// DELETE endpoint.
@attached(peer)
public macro Delete(_ path: String = "", task: _TaskKind = .data, query: [String: String] = [:], headers: [String: String] = [:], timeout: Duration? = nil, retry: RetryPolicy = .standard, auth: AuthPolicy? = nil, json: JSONCoding? = nil) = #externalMacro(module: "BeamMacros", type: "DeleteMacro")

/// PATCH endpoint.
@attached(peer)
public macro Patch(_ path: String = "", task: _TaskKind = .data, query: [String: String] = [:], headers: [String: String] = [:], timeout: Duration? = nil, retry: RetryPolicy = .standard, auth: AuthPolicy? = nil, json: JSONCoding? = nil) = #externalMacro(module: "BeamMacros", type: "PatchMacro")

/// HEAD endpoint.
@attached(peer)
public macro Head(_ path: String = "", task: _TaskKind = .data, query: [String: String] = [:], headers: [String: String] = [:], timeout: Duration? = nil, retry: RetryPolicy = .standard, auth: AuthPolicy? = nil, json: JSONCoding? = nil) = #externalMacro(module: "BeamMacros", type: "HeadMacro")

/// OPTIONS endpoint.
@attached(peer)
public macro Options(_ path: String = "", task: _TaskKind = .data, query: [String: String] = [:], headers: [String: String] = [:], timeout: Duration? = nil, retry: RetryPolicy = .standard, auth: AuthPolicy? = nil, json: JSONCoding? = nil) = #externalMacro(module: "BeamMacros", type: "OptionsMacro")

/// TRACE endpoint.
@attached(peer)
public macro Trace(_ path: String = "", task: _TaskKind = .data, query: [String: String] = [:], headers: [String: String] = [:], timeout: Duration? = nil, retry: RetryPolicy = .standard, auth: AuthPolicy? = nil, json: JSONCoding? = nil) = #externalMacro(module: "BeamMacros", type: "TraceMacro")

/// WebSocket endpoint (GET + upgrade). `retry` covers the first connection, `reconnect` the
/// ones after a drop; the socket options override the API's `SocketConfig`.
@attached(peer)
public macro Socket(
    _ path: String = "",
    query: [String: String] = [:],
    headers: [String: String] = [:],
    timeout: Duration? = nil,
    retry: RetryPolicy = .standard,
    auth: AuthPolicy? = nil,
    json: JSONCoding? = nil,
    ping: Duration? = nil,
    pongTimeout: Duration? = nil,
    maxMessageSize: Int? = nil,
    reconnect: RetryPolicy = .resilient,
    protocols: [String] = [],
    jsonFrames: SocketConfig.JSONFrames? = nil,
    reconnectsOn: Set<Int> = []
) = #externalMacro(module: "BeamMacros", type: "SocketMacro")

// MARK: - Supporting Types

/// Used by @API.
public enum _TaskKind: Sendable {
    case data
    case upload
    case download
    case bytes
}

// MARK: - API Configuration

/// What every route of an API shares; `@API` builds one, an ``Endpoint`` used by hand takes one.
/// `host`, `base` and `headers` are re-evaluated on every access, from any thread.
public struct APIConfiguration: Sendable {
    public private(set) var session: any SessionProtocol
    public let background: Session<Background>?
    public let auth: (any AuthProtocol)?
    public let monitors: [any Monitor]
    public let config: RequestConfig
    public let socket: SocketConfig
    public let interceptors: [any Interceptor]
    public let logLevel: LogLevel?

    private let hostProvider: @Sendable () -> String
    private let baseProvider: @Sendable () -> String
    private let headersProvider: @Sendable () -> [String: String]

    public var host: String { hostProvider() }
    public var base: String { baseProvider() }
    public var headers: [String: String] { headersProvider() }

    public init(
        host: @autoclosure @escaping @Sendable () -> String,
        base: @autoclosure @escaping @Sendable () -> String = "",
        headers: @autoclosure @escaping @Sendable () -> [String: String] = [:],
        session: any SessionProtocol = Session(),
        background: Session<Background>? = nil,
        auth: (any AuthProtocol)? = nil,
        monitors: [any Monitor] = [],
        config: RequestConfig = .standard,
        socket: SocketConfig = .standard,
        interceptors: [any Interceptor] = [],
        logLevel: LogLevel? = nil
    ) {
        self.hostProvider = host
        self.baseProvider = base
        self.headersProvider = headers
        self.session = session
        self.background = background
        self.auth = auth
        self.monitors = monitors
        self.config = config
        self.socket = socket
        self.interceptors = interceptors
        self.logLevel = logLevel
    }

    /// A copy that uses `session`, or `self` when `session` is `nil`.
    public func replacing(session: (any SessionProtocol)?) -> APIConfiguration {
        guard let session else { return self }
        var copy = self
        copy.session = session
        return copy
    }

    /// A request for a route of this API; `values` fill the `{name}` placeholders of `path`.
    public func request(
        _ method: HTTPMethod,
        _ path: String,
        values: [String: String] = [:],
        query: [URLQueryItem] = [],
        headers: [String: String]? = nil,
        body: HTTPBody? = nil
    ) -> APIRequest {
        _request(method, path, values: values.mapValues(_Route.Value.value), query: query, headers: headers, body: body)
    }

    /// A request to an absolute URL, ignoring `host` and `base`.
    /// - Parameter route: Name that groups its error reports, e.g. `"DocumentsAPI.download"`.
    public func request(
        _ method: HTTPMethod,
        url: URL,
        route: String,
        headers: [String: String]? = nil,
        body: HTTPBody? = nil
    ) -> APIRequest {
        APIRequest(method: method, host: url.absoluteString, path: "", pathTemplate: route, headers: headers ?? self.headers, body: body)
    }

    /// Used by @API.
    public func _request(
        _ method: HTTPMethod,
        _ path: String,
        values: [String: _Route.Value] = [:],
        routeQuery: KeyValuePairs<String, _Route.Value> = [:],
        query: [URLQueryItem] = [],
        headers: [String: String]? = nil,
        body: HTTPBody? = nil
    ) -> APIRequest {
        let headers = headers ?? self.headers
        let base = base
        let resolved = RoutePath(base: base, template: path, values: values)
        var missing = resolved.missing

        var items: [URLQueryItem] = []
        for (name, value) in routeQuery {
            switch value {
            case .value(let text): items.append(URLQueryItem(name: name, value: text))
            case .omitted: break
            case .missing(let valueName): missing = missing ?? valueName
            }
        }

        var request = APIRequest(
            method: method,
            host: host,
            path: resolved.path,
            pathTemplate: base + path,
            query: items + query,
            headers: headers,
            body: body
        )
        request.percentEncodedPath = resolved.percentEncodedPath
        request.missingValue = missing
        return request
    }
}

// MARK: - Route Path

struct RoutePath {
    let path: String
    /// Each placeholder value is encoded as one segment, so a `/` in it stays escaped.
    let percentEncodedPath: String
    let missing: String?

    private static let pathAllowed = CharacterSet.urlPathAllowed
    private static let segmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))

    init(base: String, template: String, values: [String: _Route.Value]) {
        var path = base
        var encoded = Self.encode(base, allowing: Self.pathAllowed)
        var missing: String?

        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            let literal = String(rest[..<open])
            path += literal
            encoded += Self.encode(literal, allowing: Self.pathAllowed)

            guard let close = rest[open...].firstIndex(of: "}") else {
                rest = rest[open...]
                break
            }
            let name = String(rest[rest.index(after: open)..<close])
            let placeholder = String(rest[open...close])

            if case .value(let text) = values[name] {
                path += text
                encoded += Self.encode(text, allowing: Self.segmentAllowed)
            } else {
                // Unresolved placeholders are kept as written.
                if case .missing(let valueName) = values[name] { missing = missing ?? valueName }
                if case .omitted = values[name] { missing = missing ?? name }
                path += placeholder
                encoded += Self.encode(placeholder, allowing: Self.pathAllowed)
            }
            rest = rest[rest.index(after: close)...]
        }
        path += rest
        encoded += Self.encode(String(rest), allowing: Self.pathAllowed)

        self.path = path
        self.percentEncodedPath = encoded
        self.missing = missing
    }

    private static func encode(_ text: String, allowing allowed: CharacterSet) -> String {
        text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

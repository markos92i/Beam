//
//  SocketEndpoint.swift
//  Beam
//
//  Dedicated endpoint for WebSocket connections.
//  Separated from Endpoint to maintain single-responsibility:
//  Endpoint handles HTTP (data/upload/download), SocketEndpoint handles WebSocket.
//

import Foundation

// MARK: - SocketEndpoint

public struct SocketEndpoint<Message: Sendable, Failure: Sendable>: Sendable {
    public let id = String(UUID().uuidString.prefix(4))

    let log: BeamLogger
    public let session: any SessionProtocol
    public let auth: (any AuthProtocol)?
    public let mapper: any MapperProtocol
    public let config: RequestConfig
    public let authPolicy: AuthPolicy
    public let interceptors: [any RequestInterceptor]
    public let api: APIRequest

    public init(
        session: any SessionProtocol = URLSession.shared,
        auth: (any AuthProtocol)? = nil,
        mapper: any MapperProtocol = Mapper(),
        config: RequestConfig = .standard,
        authPolicy: AuthPolicy = .required,
        interceptors: [any RequestInterceptor] = [],
        logLevel: LogLevel? = nil,
        api: APIRequest
    ) {
        self.session = session
        self.auth = auth
        self.mapper = mapper
        self.config = config
        self.authPolicy = authPolicy
        self.interceptors = interceptors
        self.api = api
        self.log = BeamLogger(level: logLevel)
    }

    // MARK: - Connect

    /// Connects and returns an active `WebSocketConnection`.
    ///
    /// Includes auto-reconnection and ping keepalive based on `RequestConfig`.
    public func connect() async throws(APIError<Failure>) -> WebSocketConnection<Message, Failure> {
        let (stateStream, stateContinuation) = AsyncStream<WebSocketConnectionState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        let socket = Socket<Message, Failure>(
            session: session,
            mapper: mapper,
            config: config,
            log: log,
            id: id,
            requestBuilder: { [self] in try await self.request },
            stateContinuation: stateContinuation
        )

        let messages = try await socket.open()

        return WebSocketConnection(
            messages: messages,
            state: stateStream,
            send: { value in try await socket.send(value) },
            sendData: { data in try await socket.send(data: data) },
            sendText: { text in try await socket.send(text: text) },
            disconnect: { await socket.disconnect() }
        )
    }
}

// MARK: - Request Building

extension SocketEndpoint {
    var request: URLRequest {
        get async throws {
            guard let url = api.url else {
                throw APIError<Failure>.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = api.method.rawValue
            request.allHTTPHeaderFields = api.allHeaders
            request.timeoutInterval = config.timeout

            for interceptor in interceptors {
                request = await interceptor.intercept(request: request)
            }

            if let auth {
                switch authPolicy {
                case .required:
                    try await auth.authenticate(request: &request)
                case .optional:
                    try? await auth.authenticate(request: &request)
                }
            }

            return request
        }
    }
}

//
//  Service.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct Service<Success: Sendable, Failure: Sendable>: Sendable {
    public let id = UUID().uuidString

    private let log: Logger
    public let client: any ClientProtocol
    public let auth: (any AuthProtocol)?
    public let crash: (any CrashProtocol)?
    public let serializer: any SerializerProtocol
    public let config: RequestConfig
    public let authPolicy: AuthPolicy
    public let api: APIRequest
    
    public var progress: AsyncStream<Progress> { client.progress }

    public init(
        client: any ClientProtocol = Client(session: URLSession.shared),
        auth: (any AuthProtocol)? = nil,
        crash: (any CrashProtocol)? = nil,
        serializer: any SerializerProtocol = Serializer(),
        config: RequestConfig = .standard,
        authPolicy: AuthPolicy = .required,
        api: APIRequest
    ) {
        self.client = client
        self.auth = auth
        self.crash = crash
        self.serializer = serializer
        self.config = config
        self.authPolicy = authPolicy
        self.api = api
        self.log = Logger(output: crash)
    }
    
    // MARK: - Throwing Core Implementation
    private func perform<Output>(
        operation: (URLRequest) async throws -> Output
    ) async throws(APIError<Failure>) -> Output {
        let retryPolicy = config.retry
        for attempt in 0...retryPolicy.maxAttempts {
            do {
                if attempt > 0 { log.retry(attempt: attempt, maxRetries: retryPolicy.maxAttempts) }
                let result = try await operation(try await request)
                return result
            } catch let error as ClientError {
                if error.status == .unauthorized { await auth?.invalidate() }
                
                guard attempt < retryPolicy.maxAttempts, error.isRetryable else {
                    throw await mapError(error, attempt: attempt)
                }

                let delay = retryPolicy.delay(for: attempt + 1)
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
            } catch {
                throw await mapError(error, attempt: attempt)
            }
        }
        
        throw APIError<Failure>.unknown
    }
    
    // MARK: - Run (stream-based)
    public func run<T: Sendable>(_ operation: @escaping @Sendable (Service) async throws -> T) -> AsyncStream<RunEvent<T, Failure>> {
        let (stream, continuation) = AsyncStream<RunEvent<T, Failure>>.makeStream()
        let selfCopy = self
        Task {
            let progressTask = Task {
                for await p in selfCopy.progress { continuation.yield(.progress(p)) }
            }
            do {
                let result = try await operation(selfCopy)
                progressTask.cancel()
                continuation.yield(.success(result))
            } catch let error as APIError<Failure> {
                progressTask.cancel()
                continuation.yield(.failure(error))
            } catch {
                progressTask.cancel()
                continuation.yield(.failure(.cancelled))
            }
            continuation.finish()
        }
        return stream
    }

    public func data() async throws(APIError<Failure>) -> Success {
        if let cacheFile = api.cacheFile { return try await file(file: cacheFile) }
        return try await perform() { request in
            var request = request
            request.httpBody = try api.data(with: serializer)
            let response: Data = try await client.data(for: request)
            return try serializer.decode(data: response)
        }
    }
    
    public func upload() async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            guard let body = try api.data(with: serializer) else { throw APIError<Failure>.missingUploadData }
            let response: Data = try await client.upload(for: request, data: body)
            return try serializer.decode(data: response)
        }
    }
    
    public func upload(url: URL) async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            let response: Data = try await client.upload(for: request, url: url)
            return try serializer.decode(data: response)
        }
    }

    public func upload(resumeFrom data: Data) async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            let response: Data = try await client.upload(for: request, resumeFrom: data)
            return try serializer.decode(data: response)
        }
    }
    
    public func download() async throws(APIError<Failure>) -> URL {
        try await perform() { request in
            let response = try await client.download(for: request)
            return try FileUtils.copy(url: response.url, to: .cachesDirectory, contentType: response.contentType)
        }
    }
    
    public func download(resumeFrom data: Data) async throws(APIError<Failure>) -> URL {
        try await perform() { request in
            let response = try await client.download(for: request, resumeFrom: data)
            return try FileUtils.copy(url: response.url, to: .cachesDirectory, contentType: response.contentType)
        }
    }

    public func file(file: String) async throws(APIError<Failure>) -> Success {
        do {
            guard let url = Bundle.main.url(forResource: file, withExtension: nil) else {
                throw APIError<Failure>.invalidURL
            }
            let data = try Data(contentsOf: url)
            return try serializer.decode(data: data)
        } catch {
            throw await mapError(error, attempt: 0)
        }
    }
        
    public func cancel() async -> Data? {
        await client.cancel()
    }

    // MARK: - WebSocket

    /// Opens a WebSocket connection and returns a stream of deserialized messages.
    private func rawStream() async throws(APIError<Failure>) -> AsyncThrowingStream<Success, Error> {
        let request: URLRequest
        do {
            request = try await self.request
        } catch let error as AuthError {
            throw APIError<Failure>(from: error)
        } catch let error as APIError<Failure> {
            throw error
        } catch {
            throw APIError<Failure>.unknown
        }

        do {
            let stream: AsyncThrowingStream<URLSessionWebSocketTask.Message, Error> = try await client.webSocket(for: request)
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        for try await message in stream {
                            let decoded: Success = try deserialize(message: message)
                            continuation.yield(decoded)
                        }
                        continuation.finish()
                    } catch let error as SerializerError {
                        continuation.finish(throwing: APIError<Failure>(from: error))
                    } catch {
                        let serviceError = parseError(error)
                        continuation.finish(throwing: serviceError)
                    }
                }
            }
        } catch {
            throw await mapError(error, attempt: 0)
        }
    }

    // MARK: - Reconnection-Aware Stream

    /// Opens a WebSocket connection with automatic reconnection and optional ping/pong keepalive.
    /// Retry policy and ping interval are read from the service's `config`.
    public func stream() async throws(APIError<Failure>) -> AsyncThrowingStream<StreamEvent<Success, Failure>, Error> {
        let state = WebSocketStreamState<Success, Failure>()
        let service = self
        let retryPolicy = config.retry

        // Validate pingInterval is in allowed range
        let effectivePingInterval: TimeInterval? = if let interval = config.pingInterval,
            interval >= 1, interval <= 300 { interval } else { nil }

        let (eventStream, eventContinuation) = AsyncThrowingStream<StreamEvent<Success, Failure>, Error>.makeStream()
        state.streamContinuation = eventContinuation

        // Termination handler: clean up ping task when stream is consumed or cancelled
        eventContinuation.onTermination = { @Sendable _ in
            state.intentionalDisconnect = true
            state.pingTask?.cancel()
            state.pingTask = nil
        }

        Task { [service, state, retryPolicy, effectivePingInterval] in
            var currentAttempt = 0

            // Outer loop: handles connection and reconnection
            connectionLoop: while !state.intentionalDisconnect {
                // Attempt to establish the WebSocket connection
                let messageStream: AsyncThrowingStream<Success, Error>
                do {
                    messageStream = try await service.rawStream()
                } catch let error as APIError<Failure> {
                    // If we're reconnecting and this attempt failed, try next
                    if state.isReconnecting {
                        currentAttempt += 1
                        if currentAttempt > retryPolicy.maxAttempts {
                            eventContinuation.finish(throwing: APIError<Failure>.serverUnreachable)
                            break connectionLoop
                        }
                        // Emit reconnecting event for next attempt
                        eventContinuation.yield(.reconnecting(attempt: currentAttempt, maxAttempts: retryPolicy.maxAttempts))
                        // Wait before retry
                        let delay = retryPolicy.delay(for: currentAttempt)
                        service.log.webSocketReconnect(rid: String(service.id.prefix(4)), attempt: currentAttempt, delay: delay)
                        do {
                            try await Task.sleep(for: .seconds(delay))
                        } catch {
                            // Task cancelled (intentional disconnect during sleep)
                            if !state.intentionalDisconnect {
                                eventContinuation.finish(throwing: APIError<Failure>.cancelled)
                            } else {
                                eventContinuation.finish()
                            }
                            break connectionLoop
                        }
                        continue connectionLoop
                    }
                    // Not reconnecting — initial connection failure
                    eventContinuation.finish(throwing: error)
                    break connectionLoop
                } catch {
                    eventContinuation.finish(throwing: error)
                    break connectionLoop
                }

                // If we just reconnected successfully, emit .reconnected
                if state.isReconnecting {
                    state.isReconnecting = false
                    currentAttempt = 0
                    eventContinuation.yield(.reconnected)
                }

                // Start ping timer if configured
                if let interval = effectivePingInterval {
                    state.pingTask?.cancel()
                    state.pingTask = Task { [service, state, retryPolicy] in
                        while !Task.isCancelled && !state.intentionalDisconnect {
                            do {
                                try await Task.sleep(for: .seconds(interval))
                            } catch {
                                break // Task cancelled
                            }

                            guard !state.intentionalDisconnect else { break }

                            // Send ping and wait for pong within pingInterval seconds
                            let pongReceived = await withTaskGroup(of: Bool.self) { group in
                                group.addTask {
                                    do {
                                        try await service.ping()
                                        return true
                                    } catch {
                                        return false
                                    }
                                }
                                group.addTask {
                                    do {
                                        try await Task.sleep(for: .seconds(interval))
                                        return false // Timeout
                                    } catch {
                                        return true // Cancelled = pong arrived first (group cancelled)
                                    }
                                }

                                // First result wins
                                if let first = await group.next() {
                                    group.cancelAll()
                                    return first
                                }
                                return false
                            }

                            if !pongReceived && !state.intentionalDisconnect {
                                // Pong timeout — treat as disconnection
                                if retryPolicy.maxAttempts > 0 {
                                    // Trigger reconnection by disconnecting the underlying connection
                                    await service.disconnect(code: .abnormalClosure, reason: nil)
                                } else {
                                    // No reconnection strategy: finish stream with error
                                    eventContinuation.finish(
                                        throwing: APIError<Failure>.connectionClosed(code: 1006, reason: nil)
                                    )
                                    await service.disconnect(code: .abnormalClosure, reason: nil)
                                }
                                break
                            }
                        }
                    }
                }

                // Consume messages from the underlying stream
                do {
                    for try await message in messageStream {
                        guard !state.intentionalDisconnect else { break }
                        eventContinuation.yield(.message(message))
                    }

                    // Stream finished without error — normal closure
                    if state.intentionalDisconnect {
                        eventContinuation.finish()
                        break connectionLoop
                    }

                    // If we get here without intentional disconnect, it's a clean server close.
                    // Don't reconnect on normal closure.
                    eventContinuation.finish()
                    break connectionLoop
                } catch let error as APIError<Failure> {
                    // Stop ping timer
                    state.pingTask?.cancel()
                    state.pingTask = nil

                    guard !state.intentionalDisconnect else {
                        eventContinuation.finish()
                        break connectionLoop
                    }

                    // Check if this is an unexpected close that should trigger reconnection
                    let shouldReconnect: Bool = {
                        guard retryPolicy.maxAttempts > 0 else { return false }
                        switch error {
                        case .connectionClosed(let code, _):
                            // 1000 = normal closure, don't reconnect
                            // 1001 = going away (client-sent), don't reconnect
                            return code != 1000 && code != 1001
                        case .noConnection, .timedOut, .serverUnreachable, .unknown:
                            return true
                        default:
                            return false
                        }
                    }()

                    if shouldReconnect {
                        state.isReconnecting = true
                        currentAttempt = 1

                        if currentAttempt > retryPolicy.maxAttempts {
                            eventContinuation.finish(throwing: APIError<Failure>.serverUnreachable)
                            break connectionLoop
                        }

                        // Emit first reconnecting event
                        eventContinuation.yield(.reconnecting(attempt: currentAttempt, maxAttempts: retryPolicy.maxAttempts))

                        // Wait before retry
                        let delay = retryPolicy.delay(for: currentAttempt)
                        service.log.webSocketReconnect(rid: String(service.id.prefix(4)), attempt: currentAttempt, delay: delay)
                        do {
                            try await Task.sleep(for: .seconds(delay))
                        } catch {
                            if !state.intentionalDisconnect {
                                eventContinuation.finish(throwing: APIError<Failure>.cancelled)
                            } else {
                                eventContinuation.finish()
                            }
                            break connectionLoop
                        }
                        continue connectionLoop
                    } else {
                        // Non-reconnectable error — propagate
                        eventContinuation.finish(throwing: error)
                        break connectionLoop
                    }
                } catch {
                    // Stop ping timer
                    state.pingTask?.cancel()
                    state.pingTask = nil

                    if state.intentionalDisconnect {
                        eventContinuation.finish()
                    } else {
                        eventContinuation.finish(throwing: error)
                    }
                    break connectionLoop
                }
            }

            // Cleanup
            state.pingTask?.cancel()
            state.pingTask = nil
        }

        return eventStream
    }

    /// Sends a typed value over the active WebSocket connection.
    public func send(_ value: Success) async throws(APIError<Failure>) {
        let data: Data
        do {
            data = try serializer.encode(value)
        } catch let error as SerializerError {
            throw APIError<Failure>(from: error)
        } catch {
            throw APIError<Failure>.encode
        }

        do {
            try await client.send(message: .data(data))
        } catch {
            throw await mapError(error, attempt: 0)
        }
    }

    /// Sends raw data as a binary WebSocket message.
    public func send(data: Data) async throws(APIError<Failure>) {
        do {
            try await client.send(message: .data(data))
        } catch {
            throw await mapError(error, attempt: 0)
        }
    }

    /// Sends a string as a text WebSocket message.
    public func send(text: String) async throws(APIError<Failure>) {
        do {
            try await client.send(message: .string(text))
        } catch {
            throw await mapError(error, attempt: 0)
        }
    }

    /// Disconnects the WebSocket connection.
    public func disconnect(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) async {
        await client.disconnect(code: code, reason: reason)
    }

    /// Sends a ping frame.
    public func ping() async throws(APIError<Failure>) {
        do {
            try await client.ping()
        } catch {
            throw await mapError(error, attempt: 0)
        }
    }

    // MARK: - Private WebSocket Helpers

    private func deserialize(message: URLSessionWebSocketTask.Message) throws -> Success {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else {
                throw SerializerError.incorrect
            }
            return try serializer.decode(data: data)
        case .data(let data):
            return try serializer.decode(data: data)
        @unknown default:
            throw SerializerError.unsuported
        }
    }
}

extension Service {
    // MARK: - Private Helpers
    private var defaultAcceptHeader: [String: String]? {
        switch Success.self {
        case is Data.Type: ["Accept": "application/octet-stream"]
        case is String.Type, is Bool.Type: ["Accept": "text/plain; charset=utf-8"]
        case is Void.Type: ["Accept": "*/*"]
        #if canImport(UIKit)
        case is UIImage.Type: ["Accept": "image/*"]
        #endif
        case is Codable.Type: ["Accept": "application/json"]
        default: nil
        }
    }

    private var request: URLRequest {
        get async throws {
            guard let base = URL(string: api.host),
                  var urlComponents = URLComponents(url: base.appendingPathComponent(api.path), resolvingAgainstBaseURL: true)
            else {
                throw APIError<Failure>.invalidURL
            }

            if urlComponents.queryItems != nil {
                urlComponents.queryItems?.append(contentsOf: api.params)
            } else {
                urlComponents.queryItems = api.params
            }

            guard let url = urlComponents.url else { throw APIError<Failure>.invalidURL }
            
            var request = URLRequest(url: url)
            request.httpMethod = api.method.rawValue

            var headers = api.allHeaders
            if let defaultAcceptHeader, headers["Accept"] == nil {
                headers.merge(defaultAcceptHeader) { current, _ in current }
            }

            if let auth {
                switch authPolicy {
                case .required:
                    headers = headers.merging(try await auth.authHeader) { _, new in new }
                case .optional:
                    if let authHeaders = try? await auth.authHeader {
                        headers = headers.merging(authHeaders) { _, new in new }
                    }
                }
            }

            request.allHTTPHeaderFields = headers
            request.timeoutInterval = config.timeout
            
            return request
        }
    }
}

// MARK: Error management and reporting
extension Service {
    private func mapError(_ error: Error, attempt: Int) async -> APIError<Failure> {
        let serviceError = parseError(error)
        
        guard !serviceError.isSilent else { return serviceError }

        log.error(serviceError, source: error, attempt: attempt)
        reportError(serviceError, error: error, attempt: attempt)
        
        return serviceError
    }

    private func parseError(_ error: Error) -> APIError<Failure> {
        switch error {
        case let error as APIError<Failure>:
            return error
        case let error as ClientError:
            let body: Failure? = if let data = error.body, let decoded: Failure? = try? serializer.decode(data: data) { decoded } else { nil }
            return APIError(from: error, body: body)
        case let error as URLError:
            return APIError(from: ClientError.url(error))
        case let error as AuthError:
            return APIError(from: error)
        case let error as FileError:
            return APIError(from: error)
        case let error as SerializerError:
            return APIError(from: error)
        default:
            return .unknown
        }
    }

    private func reportError(_ serviceError: APIError<Failure>, error: Error, attempt: Int) {
        var info: [String: Any] = [
            "Method": api.method.description,
            "Host": api.host,
            "Path": api.path,
            "Attempt": attempt
        ]

        if let error = error as? LoggableError { info.merge(error.info) { $1 } }

        let sanitizedPath = api.path.replacing(/\/\d+/, with: "/{id}")
        let description: String = switch error {
        case let error as SerializerError: error.info.values.first.map { "\($0)" } ?? serviceError.name
        case let error as ClientError: error.description ?? serviceError.name
        default: serviceError.name
        }

        let reportError = NSError(
            domain: "\(api.method) \(sanitizedPath) — \(serviceError.name)",
            code: serviceError.id,
            userInfo: info.merging([NSLocalizedDescriptionKey: description]) { $1 }.mapValues { "\($0)" }
        )
        crash?.report(error: reportError, info: info)
    }
}

// MARK: - WebSocket Stream State

/// Shared mutable state for the reconnection-aware stream method.
/// Access is serialized within the owning Task closure.
final class WebSocketStreamState<Success: Sendable, Failure: Sendable>: @unchecked Sendable {
    var isReconnecting = false
    var intentionalDisconnect = false
    var pingTask: Task<Void, Never>?
    var streamContinuation: AsyncThrowingStream<StreamEvent<Success, Failure>, Error>.Continuation?
}

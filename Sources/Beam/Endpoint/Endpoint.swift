//
//  Endpoint.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//

import Foundation

// MARK: - Endpoint

public struct Endpoint<Success: Sendable, Failure: Sendable>: Sendable {
    public let id = String(UUID().uuidString.prefix(4))

    let log: BeamLogger
    let client: Client
    public let session: any SessionProtocol
    public let auth: (any AuthProtocol)?
    public let crash: (any CrashProtocol)?
    public let mapper: any MapperProtocol
    public let config: RequestConfig
    public let interceptors: [any RequestInterceptor]
    public let api: APIRequest

    public var progress: Progress { client.progress }

    public init(
        session: any SessionProtocol = URLSession.shared,
        auth: (any AuthProtocol)? = nil,
        crash: (any CrashProtocol)? = nil,
        mapper: any MapperProtocol = Mapper(),
        config: RequestConfig = .standard,
        interceptors: [any RequestInterceptor] = [],
        logLevel: LogLevel? = nil,
        api: APIRequest
    ) {
        self.session = session
        self.client = Client(id: id, session: session)
        self.auth = auth
        self.crash = crash
        self.mapper = mapper
        self.config = config
        self.interceptors = interceptors
        self.api = api
        self.log = BeamLogger(level: logLevel)
    }

    // MARK: - Core (retry + interceptors)

    private func perform<Output>(
        operation: (URLRequest) async throws -> sending Output
    ) async throws(APIError<Failure>) -> Output {
        let retryPolicy = config.retry
        for attempt in 0...retryPolicy.maxAttempts {
            do {
                if attempt > 0 {
                    let delay = retryPolicy.delay(for: attempt)
                    log.log(.retry(id: id, attempt: attempt, max: retryPolicy.maxAttempts, delay: delay))
                    if delay > 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    }
                }

                var finalRequest = try await request
                for interceptor in interceptors {
                    finalRequest = await interceptor.intercept(request: finalRequest)
                }

                let result = try await operation(finalRequest)
                return result
            } catch let error as TransportError {
                if error.status == .unauthorized { await auth?.invalidate() }

                guard attempt < retryPolicy.maxAttempts, error.isRetryable else {
                    throw await mapError(error, attempt: attempt)
                }
            } catch {
                throw await mapError(error, attempt: attempt)
            }
        }

        throw APIError<Failure>.unknown
    }

    /// Applies response interceptors to a `Response` and returns the modified result.
    private func interceptResponse(_ response: Response) async -> Response {
        var result = response
        for interceptor in interceptors {
            result = await interceptor.intercept(response: result)
        }
        return result
    }

    /// Intercepts a data response and decodes it into the Success type.
    private func decodeDataResponse(_ responseData: Data, _ response: HTTPURLResponse) async throws -> Success {
        let intercepted = await interceptResponse(Response(http: response, body: .data(responseData)))
        guard case .data(let finalData) = intercepted.body else { throw APIError<Failure>.unknown }
        return try mapper.decode(data: finalData)
    }

    /// Intercepts a download response and copies the file to caches.
    private func resolveDownloadResponse(_ url: URL, _ response: HTTPURLResponse) async throws -> URL {
        let intercepted = await interceptResponse(Response(http: response, body: .file(url)))
        guard case .file(let finalURL) = intercepted.body else { throw APIError<Failure>.unknown }
        return try FileUtils.copy(
            url: finalURL,
            to: .cachesDirectory,
            suggestedFilename: intercepted.http.suggestedFilename,
            contentType: intercepted.http.mimeType ?? ContentType.data.value
        )
    }

    // MARK: - Data

    public func data() async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            var request = request
            request.httpBody = try api.body?.encode(with: mapper)
            let (responseData, response) = try await client.data(for: request)
            return try await decodeDataResponse(responseData, response)
        }
    }

    // MARK: - Upload

    public func upload() async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            guard let body = try api.body?.encode(with: mapper) else { throw APIError<Failure>.missingUploadData }
            let (responseData, response) = try await client.upload(for: request, data: body)
            return try await decodeDataResponse(responseData, response)
        }
    }

    /// Uploads the provided Data directly, bypassing httpBody from APIRequest.
    public func upload(data: Data) async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            let (responseData, response) = try await client.upload(for: request, data: data)
            return try await decodeDataResponse(responseData, response)
        }
    }

    public func upload(url: URL) async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            let (responseData, response) = try await client.upload(for: request, url: url)
            return try await decodeDataResponse(responseData, response)
        }
    }

    public func upload(resumeFrom data: Data) async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            let (responseData, response) = try await client.upload(for: request, resumeFrom: data)
            return try await decodeDataResponse(responseData, response)
        }
    }

    // MARK: - Download

    public func download() async throws(APIError<Failure>) -> URL {
        try await perform() { request in
            let (url, response) = try await client.download(for: request)
            return try await resolveDownloadResponse(url, response)
        }
    }

    public func download(resumeFrom data: Data) async throws(APIError<Failure>) -> URL {
        try await perform() { request in
            let (url, response) = try await client.download(for: request, resumeFrom: data)
            return try await resolveDownloadResponse(url, response)
        }
    }

    // MARK: - Task-based (background-compatible)

    public func downloadTask() async throws(APIError<Failure>) -> URL {
        try await perform() { request in
            let (url, response) = try await client.downloadTask(for: request)
            return try await resolveDownloadResponse(url, response)
        }
    }

    public func downloadTask(resumeFrom data: Data) async throws(APIError<Failure>) -> URL {
        try await perform() { request in
            let (url, response) = try await client.downloadTask(for: request, resumeFrom: data)
            return try await resolveDownloadResponse(url, response)
        }
    }

    public func uploadTask() async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            guard let body = try api.body?.encode(with: mapper) else { throw APIError<Failure>.missingUploadData }
            let (responseData, response) = try await client.uploadTask(for: request, from: body)
            return try await decodeDataResponse(responseData, response)
        }
    }

    public func uploadTask(data: Data) async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            let (responseData, response) = try await client.uploadTask(for: request, from: data)
            return try await decodeDataResponse(responseData, response)
        }
    }

    public func uploadTask(url: URL) async throws(APIError<Failure>) -> Success {
        try await perform() { request in
            let (responseData, response) = try await client.uploadTask(for: request, fromFile: url)
            return try await decodeDataResponse(responseData, response)
        }
    }

    // MARK: - Stream (bytes)

    public func stream() async throws(APIError<Failure>) -> ByteStream<Success> {
        try await perform() { request in
            let (bytes, response) = try await client.bytes(for: request)
            return ByteStream<Success>(bytes: bytes, response: response) { [client] in
                await client.cancel()
            }
        }
    }

    // MARK: - Cancel

    public func cancel() async -> Data? {
        await client.cancel()
    }

    // MARK: - WebSocket

    /// Connects and returns an active `WebSocketConnection`.
    ///
    /// Includes auto-reconnection and ping keepalive based on `RequestConfig`.
    public func connect() async throws(APIError<Failure>) -> WebSocketConnection<Success, Failure> {
        let (stateStream, stateContinuation) = AsyncStream<WebSocketConnectionState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        let socket = Socket<Success, Failure>(
            session: session,
            mapper: mapper,
            config: config,
            log: log,
            id: id,
            requestBuilder: { [self] in try await self.request },
            stateContinuation: stateContinuation
        )

        do {
            let messages = try await socket.open()
            return WebSocketConnection(
                messages: messages,
                state: stateStream,
                send: { (value) async throws(APIError<Failure>) in try await socket.send(value) },
                sendData: { (data) async throws(APIError<Failure>) in try await socket.send(data: data) },
                sendText: { (text) async throws(APIError<Failure>) in try await socket.send(text: text) },
                disconnect: { await socket.disconnect() }
            )
        } catch {
            throw await mapError(error, attempt: 0)
        }
    }
}

// MARK: - Request Building

extension Endpoint {
    private var acceptHeader: [String: String]? {
        let resolved = api.accept ?? ContentType.inferred(for: Success.self)
        return resolved.map { ["Accept": $0.value] }
    }

    var request: URLRequest {
        get async throws {
            guard let url = api.url else {
                throw APIError<Failure>.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = api.method.rawValue

            var headers = api.allHeaders
            if let acceptHeader, headers["Accept"] == nil {
                headers.merge(acceptHeader) { current, _ in current }
            }

            request.allHTTPHeaderFields = headers
            request.timeoutInterval = config.timeout

            if let auth {
                switch config.authPolicy {
                case .required: try await auth.authenticate(request: &request)
                case .optional: try? await auth.authenticate(request: &request)
                }
            }

            return request
        }
    }
}

// MARK: - Error Management

extension Endpoint {
    func mapError(_ error: Error, attempt: Int) async -> APIError<Failure> {
        let serviceError = APIError<Failure>(error: error) { try? mapper.decode(data: $0) }

        guard !serviceError.isSilent else { return serviceError }

        let description = (error as? LoggableError)?.logDescription ?? serviceError.detail
        log.log(.error(id: id, icon: serviceError.icon, name: serviceError.name, detail: description, attempt: attempt))
        reportError(serviceError, error: error, attempt: attempt)

        return serviceError
    }

    private func reportError(_ serviceError: APIError<Failure>, error: Error, attempt: Int) {
        let description = (error as? LoggableError)?.logDescription ?? serviceError.detail

        let info: [String: String] = [
            "Method": api.method.description,
            "Host": api.host,
            "Path": api.path,
            "Attempt": "\(attempt)",
            "ErrorDetail": description
        ]

        let reportError = NSError(
            domain: "\(api.method) \(api.pathTemplate) — \(serviceError.name)",
            code: serviceError.id,
            userInfo: info.merging([NSLocalizedDescriptionKey: description]) { $1 }
        )
        crash?.report(error: reportError, info: info)
    }
}

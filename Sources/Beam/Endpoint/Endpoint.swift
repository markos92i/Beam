//
//  Endpoint.swift
//  Beam
//
//  A route ready to be called. Each operation runs as its own `Call`.
//

import Foundation

// MARK: - Endpoint

/// A typed route ready to be called. Stateless: each call has its own id, progress and cancellation.
public struct Endpoint<Success: Sendable, Failure: Sendable>: Sendable {
    /// The services that send the route's requests.
    public let api: APIConfiguration
    /// The API's configuration, or the route's own.
    public let config: RequestConfig
    public let request: APIRequest
    /// Decodes a successful body into `Success`; downloads don't read it.
    public let responseBody: BodyDecoder<Success>
    /// Decodes an error body into the `Failure` of ``APIError/http(status:body:response:)``.
    public let errorBody: BodyDecoder<Failure>
    private(set) var mock: Mock?

    /// Reads bodies with custom decoders; otherwise they come from the types.
    public init(
        _ api: APIConfiguration,
        config: RequestConfig? = nil,
        request: APIRequest,
        response: BodyDecoder<Success>,
        error: BodyDecoder<Failure>
    ) {
        self.api = api
        self.config = config ?? api.config
        self.request = request
        self.responseBody = response
        self.errorBody = error
    }

    /// Unavailable: Beam can't read the response or error type.
    @available(*, unavailable, message: "Beam can't read the response or error type: use a Decodable, Void or BodyRepresentable type, or pass response: and error: decoders")
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        fatalError("Unavailable")
    }

    func call() -> Call<Success, Failure> {
        Call(self)
    }

    // MARK: - Data

    public func data() async throws(APIError<Failure>) -> Success {
        try await call().data()
    }

    // MARK: - Upload

    /// Uploads `content`, which interceptors and auth don't see; `resumeFrom` applies to the first attempt only.
    public func upload(_ content: UploadContent, resumeFrom: Data? = nil, onProgress: ProgressHandler? = nil) async throws(APIError<Failure>) -> Success {
        let call = self.call()
        await onProgress?(call.client.progress)
        return try await call.upload(content, resumeFrom: resumeFrom)
    }

    // MARK: - Handles

    /// A handle for an upload driven by the session delegate.
    public func uploadTask(_ content: UploadContent) -> UploadTask<Success, Failure> {
        TransferTask(call: call()) { call, resume throws(APIError<Failure>) in
            try await call.upload(content, resumeFrom: resume, via: .delegate)
        }
    }

    /// A handle for an upload on a background session; after a relaunch its result is in ``Session/finished(until:)``.
    public func backgroundUploadTask(on session: Session<Background>, _ content: UploadContent) -> BackgroundUploadTask<Success, Failure> {
        BackgroundTransferTask(call: call()) { call, id, resume throws(APIError<Failure>) in
            try await call.upload(content, resumeFrom: resume, via: .background(session, id: id))
        }
    }

    // MARK: - Streams

    /// Opens a byte stream whose elements are read as `Success`.
    public func stream() async throws(APIError<Failure>) -> ByteStream<Success> {
        try await call().stream()
    }

    /// Opens a WebSocket whose messages are read as `Success`, with the API's `SocketConfig` unless `socket` is given.
    public func connect<Outgoing>(socket: SocketConfig? = nil) async throws(APIError<Failure>) -> WebSocketConnection<Success, Outgoing, Failure> {
        try await call().connect(socket: socket ?? api.socket)
    }
}

// MARK: - Downloads

extension Endpoint where Success == URL {
    /// Downloads the file; `resumeFrom` applies to the first attempt only.
    public func download(resumeFrom: Data? = nil, onProgress: ProgressHandler? = nil) async throws(APIError<Failure>) -> URL {
        let call = self.call()
        await onProgress?(call.client.progress)
        return try await call.download(resumeFrom: resumeFrom)
    }

    /// A handle for a download driven by the session delegate.
    public func downloadTask() -> DownloadTask<Failure> {
        TransferTask(call: call()) { call, resume throws(APIError<Failure>) in
            try await call.download(resumeFrom: resume, via: .delegate)
        }
    }

    /// A handle for a download on a background session.
    public func backgroundDownloadTask(on session: Session<Background>) -> BackgroundDownloadTask<Failure> {
        BackgroundTransferTask(call: call()) { call, id, resume throws(APIError<Failure>) in
            try await call.download(resumeFrom: resume, via: .background(session, id: id))
        }
    }
}

/// Receives the call's progress before the transfer starts.
public typealias ProgressHandler = @MainActor @Sendable (Progress) -> Void

// MARK: - Mock

extension Endpoint {
    /// Answers data, upload and download calls instead of the network, skipping interceptors, auth and monitors.
    /// Byte streams and WebSockets ignore it.
    public struct Mock: @unchecked Sendable {
        let answer: (_ resume: Data?) async throws(APIError<Failure>) -> Success

        public init(_ answer: @escaping @Sendable (_ resume: Data?) async throws(APIError<Failure>) -> Success) {
            self.answer = answer
        }

        /// For `@API` clients (non-`Sendable` closure); by hand, use ``init(_:)``.
        // Disfavoured: a trailing closure matches both inits.
        @_disfavoredOverload
        public init(_unchecked answer: @escaping (_ resume: Data?) async throws(APIError<Failure>) -> Success) {
            self.answer = answer
        }
    }

    /// The same endpoint answered by `mock`; `nil` restores the network.
    public func mocking(_ mock: Mock?) -> Endpoint {
        var copy = self
        copy.mock = mock
        return copy
    }
}

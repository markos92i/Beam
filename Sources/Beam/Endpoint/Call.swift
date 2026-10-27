//
//  Call.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//
//  The orchestration layer: one call to one route. The attempt loop lives in
//  Call+Perform and WebSocket connections in Call+Connection. `Endpoint` describes
//  the route and starts a call for each operation.
//

import Foundation
import Logy

// MARK: - Call

struct Call<Success: Sendable, Failure: Sendable>: Sendable {
    let endpoint: Endpoint<Success, Failure>
    let log: BeamLogger
    let client: Client

    var id: String { client.id }

    var route: APIRequest { endpoint.request }
    var config: RequestConfig { endpoint.config }
    var errorBody: BodyDecoder<Failure> { endpoint.errorBody }
    var session: any SessionProtocol { endpoint.api.session }
    var auth: (any AuthProtocol)? { endpoint.api.auth }
    var monitors: [any Monitor] { endpoint.api.monitors }
    var interceptors: [any Interceptor] { endpoint.api.interceptors }

    init(_ endpoint: Endpoint<Success, Failure>) {
        self.endpoint = endpoint
        self.log = BeamLogger(level: endpoint.api.logLevel)
        self.client = Client(session: endpoint.api.session, logLevel: endpoint.api.logLevel)
    }

    // MARK: - Data

    func data() async throws(APIError<Failure>) -> Success {
        if let mock = endpoint.mock { return try await mocked(mock, resume: nil) }
        return try await perform(.data, accept: endpoint.responseBody.accept) { request, _ throws(APIError<Failure>) in
            let (data, response) = try await transport { () throws(TransportError) in try await client.data(for: request) }
            return Response(http: response, body: .data(data))
        } output: { response throws(APIError<Failure>) in
            try await decode(response)
        }
    }

    // MARK: - Transfers

    enum Path: Sendable {
        case native
        case delegate
        /// Starting again with an `id` in flight on the same route attaches to that transfer.
        case background(Session<Background>, id: String)
    }

    func upload(_ content: UploadContent, resumeFrom resumeData: Data? = nil, via path: Path = .native) async throws(APIError<Failure>) -> Success {
        if let mock = endpoint.mock { return try await mocked(mock, resume: resumeData) }
        return try await perform(.upload, accept: endpoint.responseBody.accept, uploading: content, resumeFrom: resumeData) { request, payload throws(APIError<Failure>) in
            // Never nil for uploads: content or resume data.
            let payload = payload ?? .data(Data())
            let (data, response) = try await transport { () throws(TransportError) in
                switch path {
                case .native: try await client.upload(for: request, payload)
                case .delegate: try await client.uploadTask(for: request, payload)
                case .background(let session, let id): try await client.backgroundUpload(on: session, key: route.backgroundKey(id), request: request, payload)
                }
            }
            return Response(http: response, body: .data(data))
        } output: { response throws(APIError<Failure>) in
            try await decode(response)
        }
    }

    // MARK: - Stream (bytes)

    func stream() async throws(APIError<Failure>) -> ByteStream<Success> {
        var bytes: URLSession.AsyncBytes?
        return try await perform(.stream, accept: endpoint.responseBody.accept) { request, _ throws(APIError<Failure>) in
            let (stream, response) = try await transport { () throws(TransportError) in try await client.bytes(for: request) }
            bytes = stream
            guard response.httpStatus.succeeds(for: .stream) else {
                // Read the error body so interceptors and validation can see it.
                let body = await Self.collect(stream, limit: HTTPErrorBody<Void>.limit)
                stream.task.cancel()
                return Response(http: response, body: .data(body))
            }
            return Response(http: response, body: .stream)
        } output: { [elements = ElementDecoder(endpoint.responseBody, json: config.json, log: log, id: id)] response throws(APIError<Failure>) in
            guard let bytes else { throw .coding(.typeMismatch) }
            let task = bytes.task
            return ByteStream<Success>(bytes: bytes, response: response.http, elements: elements) {
                task.cancel()
            }
        }
    }
}

// MARK: - Downloads

extension Call where Success == URL {
    func download(resumeFrom resumeData: Data? = nil, via path: Path = .native) async throws(APIError<Failure>) -> URL {
        if let mock = endpoint.mock { return try await mocked(mock, resume: resumeData) }
        // Deleted unless stored: error status, rejection, retry or storage failure.
        var unclaimed: URL?
        defer { if let unclaimed { FileUtils.discard(unclaimed) } }
        return try await perform(.download, resumeFrom: resumeData) { request, payload throws(APIError<Failure>) in
            if let previous = unclaimed { FileUtils.discard(previous) }
            unclaimed = nil
            let resume: Data? = if case .resume(let data)? = payload { data } else { nil }
            let (url, response) = try await transport { () throws(TransportError) in
                switch path {
                case .native: try await client.download(for: request, resumeFrom: resume)
                case .delegate: try await client.downloadTask(for: request, resumeFrom: resume)
                case .background(let session, let id): try await client.backgroundDownload(on: session, key: route.backgroundKey(id), request: request, resumeFrom: resume)
                }
            }
            unclaimed = url
            return Response(http: response, body: .file(url))
        } output: { response throws(APIError<Failure>) in
            let stored = try await store(response)
            unclaimed = nil
            return stored
        }
    }
}

// MARK: - Operation steps

extension Call {
    func mocked(_ mock: Endpoint<Success, Failure>.Mock, resume: Data?) async throws(APIError<Failure>) -> Success {
        let value = try await mock.answer(resume)
        if Task.isCancelled { throw .cancelled }
        return value
    }

    func transport<T>(_ call: () async throws(TransportError) -> T) async throws(APIError<Failure>) -> T {
        do { return try await call() } catch { throw APIError(error) }
    }

    /// `@concurrent` keeps decoding off the caller's actor even under `NonisolatedNonsendingByDefault`.
    @concurrent
    func decode(_ response: Response) async throws(APIError<Failure>) -> Success {
        guard case .data(let data) = response.body else { throw .coding(.typeMismatch) }
        do { return try endpoint.responseBody.decode(data, with: config.json) } catch { throw .coding(error) }
    }

    /// `@concurrent` keeps the file move off the caller's actor.
    @concurrent
    func store(_ response: Response) async throws(APIError<Failure>) -> URL {
        guard case .file(let url) = response.body else { throw .coding(.typeMismatch) }
        do {
            return try FileUtils.store(url, for: response.http)
        } catch {
            throw .storage(error)
        }
    }

    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async -> Data {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= limit { break }
            }
        } catch {
            // The status already tells the failure; the body is only extra detail.
        }
        return data
    }
}

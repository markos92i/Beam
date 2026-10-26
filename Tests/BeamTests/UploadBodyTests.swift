//
//  UploadBodyTests.swift
//  Beam
//
//  What an upload sends is not part of the request, as in URLSession: interceptors and
//  auth never see it, whatever its source, and it is uploaded as given.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

/// Records the body it sees and replaces it, as a signing interceptor might.
private final class Signer: Interceptor {
    let seen = Mutex<[Data?]>([])

    func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
        seen.withLock { $0.append(request.httpBody) }
        var request = request
        if let body = request.httpBody { request.httpBody = body + Data("-signed".utf8) }
        return request
    }
}

/// An `Encodable` that can't be encoded.
private struct Unencodable: Encodable, Sendable {
    func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "no"))
    }
}

@Suite
struct UploadBodyTests {
    private static let payload = UploadContent.body(.data(Data("payload".utf8), contentType: .text))

    private static func session(status: Int = 200) -> MockSession {
        MockSession({ (request) throws(URLError) in
            (json(ResponseMock(id: "ok", value: 1)), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
    }

    /// An upload's request: what is uploaded is given to the upload.
    private static func endpoint(
        _ session: MockSession,
        body: HTTPBody? = nil,
        interceptors: [any Interceptor] = [],
        monitors: [any Monitor] = []
    ) -> Endpoint<ResponseMock, Void> {
        Endpoint(
            session: session,
            monitors: monitors,
            config: RequestConfig(retry: .none),
            interceptors: interceptors,
            api: APIRequest(method: .post, host: "https://base-url.com", path: "/upload", body: body)
        )
    }

    @Test
    func interceptorsDontSeeABodyAndItIsUploadedAsGiven() async throws {
        let session = Self.session()
        let signer = Signer()
        _ = try await Self.endpoint(session, interceptors: [signer]).upload(Self.payload)
        #expect(signer.seen.withLock { $0 } == [nil])
        #expect(await session.recordedUploads == [Data("payload".utf8)])
        #expect(await session.recordedRequests.last?.httpBody == nil)
    }

    @Test
    func interceptorsDontSeeAFile() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        try Data("file".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let signer = Signer()
        _ = try await Self.endpoint(Self.session(), interceptors: [signer]).upload(.file(file))
        #expect(signer.seen.withLock { $0 } == [nil])
    }

    /// The content type of a body goes in the request's headers, where interceptors see it.
    @Test
    func theRequestGetsTheContentTypeOfTheBody() async throws {
        let session = Self.session()
        _ = try await Self.endpoint(session).upload(Self.payload)
        #expect(await session.recordedRequests.last?.value(forHTTPHeaderField: "Content-Type") == ContentType.text.value)
    }

    /// A header the request sets wins over the body's content type.
    @Test
    func aContentTypeHeaderWinsOverTheBodys() async throws {
        let session = Self.session()
        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .post, host: "https://base-url.com", path: "/upload", headers: ["Content-Type": "application/custom"])
        )
        _ = try await endpoint.upload(Self.payload)
        #expect(await session.recordedRequests.last?.value(forHTTPHeaderField: "Content-Type") == "application/custom")
    }

    /// The request's own body would be dropped: the call fails before sending anything.
    @Test
    func aRequestWithABodyOfItsOwnCantUpload() async {
        let session = Self.session()
        do {
            _ = try await Self.endpoint(session, body: .data(Data("own".utf8))).upload(Self.payload)
            Issue.record("Expected conflictingUploadData")
        } catch {
            #expect(error == .conflictingUploadData)
        }
        #expect(await session.recordedRequests.isEmpty)
    }

    /// As in a data call: a body that can't be encoded fails before anything is sent,
    /// so the monitors never see a request go out.
    @Test
    func aBodyThatCantBeEncodedFailsBeforeSending() async {
        let sends = Mutex(0)
        let monitor = ClosureMonitor(didSend: { _, _ in sends.withLock { $0 += 1 } })
        let session = Self.session()
        do {
            _ = try await Self.endpoint(session, monitors: [monitor]).upload(.body(.json(Unencodable())))
            Issue.record("Expected an encoding error")
        } catch {
            #expect(error == .encode)
        }
        #expect(sends.withLock { $0 } == 0)
        #expect(await session.recordedUploads.isEmpty)
    }

    /// What is uploaded isn't in the request, so a failure report can't include it.
    @Test
    func aFailedUploadsReportHasNoBody() async {
        let report = Mutex<ErrorReport?>(nil)
        let monitor = ClosureMonitor(didFail: { failure, _ in report.withLock { $0 = failure.report(including: [.requestBody()]) } })
        _ = try? await Self.endpoint(Self.session(status: 400), monitors: [monitor]).upload(Self.payload)
        #expect(report.withLock { $0 } != nil)
        #expect(report.withLock { $0?.info["RequestBody"] } == nil)
    }
}

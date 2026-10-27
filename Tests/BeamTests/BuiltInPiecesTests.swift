//
//  BuiltInPiecesTests.swift
//  Beam
//
//  The ready-made pieces Beam offers to apps: built-in interceptors, the closure
//  monitor and typed Server-Sent Events.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

@Suite
struct BuiltInPiecesTests {
    private static func ok(_ request: URLRequest, status: Int = 200, body: Data = json(ResponseMock(id: "ok", value: 1))) -> (Data, URLResponse) {
        (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private static func endpoint(
        _ session: MockSession,
        interceptors: [any Interceptor] = [],
        monitors: [any Monitor] = [],
        retry: RetryPolicy = .none
    ) -> Endpoint<ResponseMock, Void> {
        Endpoint(
            session: session,
            monitors: monitors,
            config: RequestConfig(retry: retry),
            interceptors: interceptors,
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/items")
        )
    }

    // MARK: - Interceptors

    @Test
    func dynamicHeadersAreResolvedOnEveryRequest() async throws {
        let calls = Mutex(0)
        let session = MockSession({ (request) throws(URLError) in Self.ok(request) })
        let headers = DynamicHeadersInterceptor {
            ["X-Call": String(calls.withLock { $0 += 1; return $0 })]
        }

        for _ in 0..<2 {
            _ = try await Self.endpoint(session, interceptors: [headers]).data()
        }

        let sent = await session.recordedRequests.map { $0.value(forHTTPHeaderField: "X-Call") }
        #expect(sent == ["1", "2"])
    }

    @Test
    func everyRequestGetsItsOwnRequestID() async throws {
        let session = MockSession({ (request) throws(URLError) in Self.ok(request) })

        for _ in 0..<2 {
            _ = try await Self.endpoint(session, interceptors: [RequestIDInterceptor()]).data()
        }
        _ = try await Self.endpoint(session, interceptors: [RequestIDInterceptor(headerName: "X-Trace")]).data()

        let requests = await session.recordedRequests
        let ids = requests.prefix(2).compactMap { $0.value(forHTTPHeaderField: "X-Request-ID") }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(ids.allSatisfy { UUID(uuidString: $0) != nil })
        #expect(requests.last?.value(forHTTPHeaderField: "X-Trace") != nil)
    }

    // MARK: - ClosureMonitor

    @Test
    func aClosureMonitorSeesASuccessfulCall() async throws {
        let events = Mutex<[String]>([])
        let monitor = ClosureMonitor(
            didSend: { _, _ in events.withLock { $0.append("send") } },
            didReceive: { response, _ in events.withLock { $0.append("receive \(response.http.statusCode)") } },
            didSucceed: { _, _ in events.withLock { $0.append("succeed") } },
            didFail: { _, _ in events.withLock { $0.append("fail") } }
        )
        let session = MockSession({ (request) throws(URLError) in Self.ok(request) })

        _ = try await Self.endpoint(session, monitors: [monitor]).data()

        #expect(events.withLock { $0 } == ["send", "receive 200", "succeed"])
    }

    @Test
    func aClosureMonitorSeesRetriesAndTheFailure() async {
        let events = Mutex<[String]>([])
        let monitor = ClosureMonitor(
            willRetry: { error, _, _ in events.withLock { $0.append("retry \(error.name)") } },
            didSucceed: { _, _ in events.withLock { $0.append("succeed") } },
            didFail: { failure, _ in events.withLock { $0.append("fail \(failure.error.name)") } }
        )
        let session = MockSession({ (request) throws(URLError) in Self.ok(request, status: 503, body: Data()) })

        _ = try? await Self.endpoint(session, monitors: [monitor], retry: .linear(delay: .zero, maxAttempts: 1))
            .data()

        #expect(events.withLock { $0 } == ["retry http(503)", "fail http(503)"])
    }

    // MARK: - Server-Sent Events

    @Test
    func sseEventsDecodesEachEventAsTheRouteDeclares() async throws {
        let text = """
            event: message
            data: {"delta":"Ho"}

            : a comment, ignored

            data: {"delta":"la"}
            id: 2


            data: {"delta":"!"}
            """
        // The last event has no blank line after it: per the SSE spec, an event cut by
        // the end of the stream is discarded.
        let session = MockSession({ (request) throws(URLError) in Self.ok(request, body: Data(text.utf8)) })

        let stream = try await StreamAPIClient(session: session).chat(body: ChatStreamRequest(prompt: "hola"))
        var chunks: [ChatChunk] = []
        for try await chunk in stream.sseEvents() { chunks.append(chunk) }

        #expect(chunks == [ChatChunk(delta: "Ho"), ChatChunk(delta: "la")])
    }

    @Test
    func sseEventsFailsTypedOnAnUndecodableEvent() async throws {
        let session = MockSession({ (request) throws(URLError) in Self.ok(request, body: Data("data: not json\n\n".utf8)) })

        let stream = try await StreamAPIClient(session: session).chat(body: ChatStreamRequest(prompt: "hola"))
        do {
            for try await _ in stream.sseEvents() {}
            Issue.record("Expected a decoding error")
        } catch {
            #expect(error == .decode)
        }
    }
}

// MARK: - Coding failures after the call

/// Records on which thread it was decoded.
struct ThreadProbe: Decodable, Sendable {
    static let decodedOnMain = Mutex<[Bool]>([])

    init(from decoder: any Decoder) throws {
        Self.decodedOnMain.withLock { $0.append(Thread.isMainThread) }
        _ = try decoder.singleValueContainer().decode(Int.self)
    }
}

@API(host: "https://base-url.com")
protocol ProbeStreamAPI {
    @Get("/numbers", task: .bytes)
    func numbers() async throws(APIError<Void>) -> ByteStream<ThreadProbe>
}

@Suite(.serialized)
struct CodingFailureTests {
    /// A ViewModel iterating on the main actor doesn't decode on it.
    @MainActor
    @Test
    func streamElementsAreDecodedOffTheConsumersActor() async throws {
        ThreadProbe.decodedOnMain.withLock { $0 = [] }
        let session = MockSession({ (request) throws(URLError) in
            (Data("1\n2\n".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })

        let stream = try await ProbeStreamAPIClient(session: session).numbers()
        for try await _ in stream.jsonLines() {}

        #expect(ThreadProbe.decodedOnMain.withLock { $0 } == [false, false])
    }

    @Test
    func aCodingFailureAfterTheCallIsAnError() {
        let event = LogEvent.codingFailed(id: "a1", what: "SSE event not decoded", detail: "keyNotFound delta")
        #expect(event.level == .error)
        let text = event.rendered(bodies: false)
        #expect(text.contains("SSE event not decoded"))
        #expect(text.contains("keyNotFound delta"))
    }

    /// Crash reports say why the server's error body didn't decode as the route's type.
    @Test
    func theReportSaysWhyTheErrorBodyDidntDecode() {
        let decodingError: CodingError
        do throws(CodingError) {
            _ = try JSONCoding.default.decode(ResponseMock.self, from: Data("<html>".utf8))
            Issue.record("Expected a decoding error")
            return
        } catch {
            decodingError = error
        }
        let failure = EndpointFailure(
            error: .http(status: .badGateway, body: HTTPErrorBody(data: Data("<html>".utf8), decodingError: decodingError)),
            request: nil, response: nil, method: .get, host: "https://base-url.com",
            path: "/items", pathTemplate: "/items", attempt: 0
        )
        #expect(failure.report.info["ErrorBodyDecoding"] == decodingError.logDescription)

        let decoded = EndpointFailure(
            error: .http(status: .badGateway), request: nil, response: nil, method: .get,
            host: "https://base-url.com", path: "/items", pathTemplate: "/items", attempt: 0
        )
        #expect(decoded.report.info["ErrorBodyDecoding"] == nil)
    }
}

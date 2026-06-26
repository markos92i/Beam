//
//  ByteStreamTests.swift
//  Beam
//
//  Tests for ByteStream (task: .bytes), SSE parser, and JSON Lines parser.
//

import Foundation
import Testing
@testable import Beam

// MARK: - Test Models

struct ChatChunk: Codable, Sendable, Equatable {
    let delta: String
}

struct FeedEvent: Codable, Sendable, Equatable {
    let id: Int
    let message: String
}

// MARK: - Test Helpers

/// Creates an AsyncStream of lines from a multi-line string (simulates a streaming source).
func mockLines(_ text: String) -> AsyncStream<String> {
    let lines = text.components(separatedBy: "\n")
    return AsyncStream { continuation in
        for line in lines {
            continuation.yield(line)
        }
        continuation.finish()
    }
}

// MARK: - SSE Parser Unit Tests

@Suite("SSE Parser")
struct SSEParserTests {

    @Test("Parses single SSE event")
    func parseSingleEvent() {
        var buffer = SSEBuffer()

        #expect(buffer.feed(line: "event: message") == nil)
        #expect(buffer.feed(line: "data: {\"delta\":\"hello\"}") == nil)

        let event = buffer.feed(line: "")
        #expect(event != nil)
        #expect(event?.event == "message")
        #expect(event?.data == "{\"delta\":\"hello\"}")
    }

    @Test("Parses multi-line data field")
    func parseMultiLineData() {
        var buffer = SSEBuffer()

        _ = buffer.feed(line: "data: line1")
        _ = buffer.feed(line: "data: line2")
        _ = buffer.feed(line: "data: line3")

        let event = buffer.feed(line: "")
        #expect(event?.data == "line1\nline2\nline3")
    }

    @Test("Ignores comment lines")
    func ignoreComments() {
        var buffer = SSEBuffer()

        #expect(buffer.feed(line: ": this is a comment") == nil)
        _ = buffer.feed(line: "data: actual")
        let event = buffer.feed(line: "")
        #expect(event?.data == "actual")
    }

    @Test("Parses id and retry fields")
    func parseIdAndRetry() {
        var buffer = SSEBuffer()

        _ = buffer.feed(line: "id: 42")
        _ = buffer.feed(line: "retry: 3000")
        _ = buffer.feed(line: "data: payload")

        let event = buffer.feed(line: "")
        #expect(event?.id == "42")
        #expect(event?.retry == 3000)
        #expect(event?.data == "payload")
    }

    @Test("Default event type is message")
    func defaultEventType() {
        var buffer = SSEBuffer()

        _ = buffer.feed(line: "data: test")
        let event = buffer.feed(line: "")
        #expect(event?.event == "message")
    }

    @Test("Skips empty data events")
    func skipEmptyData() {
        var buffer = SSEBuffer()

        let event = buffer.feed(line: "")
        #expect(event == nil)
    }

    @Test("Strips leading space from value")
    func stripLeadingSpace() {
        var buffer = SSEBuffer()

        _ = buffer.feed(line: "data:  two spaces")
        let event = buffer.feed(line: "")
        // Only first space is stripped per spec
        #expect(event?.data == " two spaces")
    }

    @Test("Handles field with no value")
    func fieldNoValue() {
        var buffer = SSEBuffer()

        _ = buffer.feed(line: "data")
        let event = buffer.feed(line: "")
        #expect(event?.data == "")
    }

    @Test("Resets state between events")
    func resetsBetweenEvents() {
        var buffer = SSEBuffer()

        _ = buffer.feed(line: "event: custom")
        _ = buffer.feed(line: "id: 1")
        _ = buffer.feed(line: "data: first")
        let first = buffer.feed(line: "")

        _ = buffer.feed(line: "data: second")
        let second = buffer.feed(line: "")

        #expect(first?.event == "custom")
        #expect(first?.id == "1")
        #expect(second?.event == "message")
        #expect(second?.id == nil)
    }
}

// MARK: - JSON Lines Decoder Tests

@Suite("JSON Lines Decoder")
struct JSONLinesDecoderTests {

    @Test("Decodes NDJSON lines")
    func decodesNDJSON() async throws {
        let lines = mockLines("""
        {"id":1,"message":"hello"}
        {"id":2,"message":"world"}
        {"id":3,"message":"end"}
        """)

        var items: [FeedEvent] = []
        for try await item in JSONLinesSequence<_, FeedEvent>(base: lines) {
            items.append(item)
        }

        #expect(items.count == 3)
        #expect(items[0] == FeedEvent(id: 1, message: "hello"))
        #expect(items[1] == FeedEvent(id: 2, message: "world"))
        #expect(items[2] == FeedEvent(id: 3, message: "end"))
    }

    @Test("Skips blank lines")
    func skipsBlankLines() async throws {
        let lines = mockLines("""
        {"id":1,"message":"a"}

        {"id":2,"message":"b"}

        """)

        var items: [FeedEvent] = []
        for try await item in JSONLinesSequence<_, FeedEvent>(base: lines) {
            items.append(item)
        }

        #expect(items.count == 2)
    }

    @Test("Throws on invalid JSON")
    func throwsOnInvalidJSON() async {
        let lines = mockLines("not valid json")

        do {
            for try await _ in JSONLinesSequence<_, FeedEvent>(base: lines) {}
            Issue.record("Expected decoding error")
        } catch {
            #expect(error is MapperError)
        }
    }
}

// MARK: - SSE Decoder Stream Tests

@Suite("SSE Decoder Stream")
struct SSEDecoderStreamTests {

    @Test("Decodes typed SSE events")
    func decodesTypedEvents() async throws {
        let lines = mockLines("""
        event: message
        data: {"delta":"Hello"}

        event: message
        data: {"delta":" World"}

        """)

        var chunks: [ChatChunk] = []
        for try await chunk in SSESequence<_, ChatChunk>(base: lines) {
            chunks.append(chunk)
        }

        #expect(chunks.count == 2)
        #expect(chunks[0] == ChatChunk(delta: "Hello"))
        #expect(chunks[1] == ChatChunk(delta: " World"))
    }

    @Test("Parses raw SSE events")
    func parsesRawEvents() async throws {
        let lines = mockLines("""
        event: start
        data: begin

        event: delta
        data: content
        id: 5

        event: done
        data: end

        """)

        var events: [SSEvent] = []
        for try await event in SSERawSequence(base: lines) {
            events.append(event)
        }

        #expect(events.count == 3)
        #expect(events[0].event == "start")
        #expect(events[0].data == "begin")
        #expect(events[1].event == "delta")
        #expect(events[1].data == "content")
        #expect(events[1].id == "5")
        #expect(events[2].event == "done")
        #expect(events[2].data == "end")
    }

    @Test("Skips SSE events with empty data")
    func skipsEmptyDataEvents() async throws {
        let lines = mockLines("""
        event: ping

        data: real

        """)

        var events: [SSEvent] = []
        for try await event in SSERawSequence(base: lines) {
            events.append(event)
        }

        // The "ping" event has no data field → no event emitted
        #expect(events.count == 1)
        #expect(events[0].data == "real")
    }

    @Test("Handles multi-line data in stream")
    func multiLineDataStream() async throws {
        let lines = mockLines("""
        data: {"delta":"line1",
        data: "more":"line2"}

        """)

        var events: [SSEvent] = []
        for try await event in SSERawSequence(base: lines) {
            events.append(event)
        }

        #expect(events.count == 1)
        #expect(events[0].data == "{\"delta\":\"line1\",\n\"more\":\"line2\"}")
    }
}

// MARK: - StreamEndpoint Error Tests

@Suite("StreamEndpoint Errors")
struct StreamEndpointErrorTests {

    @Test("Endpoint.stream() fails on network error")
    func failsOnNetworkError() async throws {
        let handler: MockSession.DataHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let session = MockSession(handler)

        let endpoint = Endpoint<String, Void>(
            session: session,
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: "https://test.com", path: "/feed")
        )

        do {
            _ = try await endpoint.stream()
            Issue.record("Expected error")
        } catch let error as APIError<Void> {
            #expect(error == .noConnection)
        }
    }

    @Test("Endpoint.stream() fails on timeout")
    func failsOnTimeout() async throws {
        let handler: MockSession.DataHandler = { _ in
            throw URLError(.timedOut)
        }
        let session = MockSession(handler)

        let endpoint = Endpoint<String, Void>(
            session: session,
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: "https://test.com", path: "/feed")
        )

        do {
            _ = try await endpoint.stream()
            Issue.record("Expected error")
        } catch let error as APIError<Void> {
            #expect(error == .timedOut)
        }
    }

    @Test("Endpoint.stream() retries then gives up")
    func retriesAndGivesUp() async throws {
        let counter = AtomicCounter()

        let handler: MockSession.DataHandler = { _ in
            await counter.increment()
            throw URLError(.timedOut)
        }
        let session = MockSession(handler)

        // .standard has 1 retry (maxAttempts: 1) → 2 total attempts
        let endpoint = Endpoint<String, Void>(
            session: session,
            api: APIRequest(method: .get, host: "https://test.com", path: "/feed")
        )

        do {
            _ = try await endpoint.stream()
            Issue.record("Expected error")
        } catch let error as APIError<Void> {
            #expect(error == .timedOut)
        }

        // Should have attempted 2 times (initial + 1 retry)
        let attempts = await counter.value
        #expect(attempts == 2)
    }
}

// MARK: - StreamAPI (compile-time macro verification)

@API(
    host: "https://stream-test.com",
    base: "/v1",
    headers: [:]
)
protocol StreamAPI {
    @Get("/feed", task: .bytes)
    func feed() async throws(APIError<Void>) -> ByteStream<FeedEvent>

    @Post("/chat", task: .bytes)
    func chat(body request: ChatStreamRequest) async throws(APIError<Void>) -> ByteStream<ChatChunk>
}

struct ChatStreamRequest: Codable, Sendable {
    let prompt: String
}

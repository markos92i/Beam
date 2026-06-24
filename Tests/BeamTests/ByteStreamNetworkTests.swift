//
//  ByteStreamNetworkTests.swift
//  Beam
//
//  Network integration tests for ByteStream using real public APIs.
//  These tests require internet access and hit external services.
//  Uses postman-echo.com (stable, finite streams that close on completion).
//

import Foundation
import Testing
@testable import Beam

// MARK: - Stream API

@API(
    host: "https://postman-echo.com",
    base: "",
    headers: [:]
)
protocol PostmanSSEAPI {
    @Get("/server-events/{count}", task: .bytes, auth: .optional)
    func events(count: Int) async throws(APIError<Void>) -> ByteStream<String>
}

// MARK: - Network Tests

@Suite("ByteStream Network", .tags(.network))
struct ByteStreamNetworkTests {

    @Test("SSE — raw lines arrive correctly from server")
    func sseRawLines() async throws {
        let stream = try await PostmanSSEAPIClient().events(count: 3)

        var lines: [String] = []
        for try await line in stream.lines {
            lines.append(line)
        }

        // 3 events × 3 lines each (event:, data:, id:) = 9 non-empty lines
        #expect(lines.count >= 9)
        #expect(lines[0].hasPrefix("event:"))
    }

    @Test("SSE — finite events parsed with correct structure")
    func sseFromPostmanEcho() async throws {
        let stream = try await PostmanSSEAPIClient().events(count: 3)

        var events: [SSEvent] = []
        for try await event in stream.sseRawEvents() {
            events.append(event)
        }

        #expect(events.count == 3)
        #expect(events[0].id == "1")
        #expect(!events[0].data.isEmpty)
        #expect(!events[0].event.isEmpty)
    }

    @Test("SSE — events have sequential IDs")
    func sseSequentialIds() async throws {
        let stream = try await PostmanSSEAPIClient().events(count: 5)

        var events: [SSEvent] = []
        for try await event in stream.sseRawEvents() {
            events.append(event)
        }

        #expect(events.count == 5)
        for (index, event) in events.enumerated() {
            #expect(event.id == "\(index + 1)")
        }
    }

    @Test("ByteStream response has valid status code")
    func responseMetadata() async throws {
        let stream = try await PostmanSSEAPIClient().events(count: 1)
        #expect(stream.response.statusCode == 200)
    }
}

//
//  JSONCodingTests.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 31/05/2026.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

@Suite
struct JSONCodingTests {
    private struct Stub: Codable, Equatable {
        var id: Int = 0
        var date: Date = Date(timeIntervalSince1970: 1780183200) // 2026-05-30T23:20:00Z
    }

    @Test
    func defaultsAreApples() throws {
        // One key: without `.sortedKeys` the order of several isn't stable.
        struct Dated: Codable, Equatable { var date = Date(timeIntervalSince1970: 1780183200) }
        let data = try JSONCoding.default.encode(Dated())
        #expect(data == (try JSONEncoder().encode(Dated())))
        #expect(try JSONCoding.default.decode(Dated.self, from: data) == Dated())
    }

    @Test
    func iso8601DatesBothWays() throws {
        let data = try JSONCoding.iso8601.encode(Stub())
        #expect(String(decoding: data, as: UTF8.self).contains(#""2026-05-30T23:20:00Z""#))
        #expect(try JSONCoding.iso8601.decode(Stub.self, from: data) == Stub())
        // Apple's default reads dates as numbers, not ISO 8601 text.
        #expect(throws: CodingError.self) { try JSONCoding.default.decode(Stub.self, from: data) }
    }

    @Test
    func everyStrategyReachesTheEncoderAndDecoder() throws {
        struct Keys: Codable, Equatable { var userId = 1 }
        let json = JSONCoding(outputFormatting: .sortedKeys, keyEncoding: .convertToSnakeCase, keyDecoding: .convertFromSnakeCase)
        let data = try json.encode(Keys())
        #expect(String(decoding: data, as: UTF8.self) == #"{"user_id":1}"#)
        #expect(try json.decode(Keys.self, from: data) == Keys())
    }

    @Test
    func formURLEncoded() throws {
        let items = [
            URLQueryItem(name: "username", value: "marcos"),
            URLQueryItem(name: "password", value: "s3cr3t&special=yes")
        ]
        let encoded = String(data: items.formEncoded(), encoding: .utf8)!

        #expect(encoded.contains("username=marcos"))
        #expect(encoded.contains("password=s3cr3t%26special%3Dyes"))
        #expect(HTTPBody.formURLEncoded(items).contentType == .urlEncoded)
    }

    @Test
    func rawDataPreservesContentType() throws {
        let httpBody = HTTPBody.data(Data("hello".utf8), contentType: .text)
        #expect(httpBody.contentType == .text)
    }
}

// MARK: - Encoding once per call

/// Counts how many times it is encoded.
private struct CountingBody: Encodable, Sendable {
    let count: Counter

    func encode(to encoder: any Encoder) throws {
        count.value.withLock { $0 += 1 }
        var container = encoder.singleValueContainer()
        try container.encode("payload")
    }
}

private final class Counter: Sendable {
    let value = Mutex(0)
}

@Suite
struct BodyEncodingTests {
    /// Regression: a byte stream route dropped its body (`POST /chat` streamed without it).
    @Test
    func aByteStreamSendsItsBody() async throws {
        let session = MockSession({ (request) throws(URLError) in
            (Data("{}\n".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await StreamAPIClient(session: session).chat(body: ChatStreamRequest(prompt: "hola"))

        let sent = try #require(await session.recordedRequests.last?.httpBody)
        #expect(try JSONDecoder().decode(ChatStreamRequest.self, from: sent).prompt == "hola")
    }

    /// Retries and the repeat after a 401 send the body encoded by the first attempt.
    @Test
    func theBodyIsEncodedOncePerCallAndSentOnEveryAttempt() async throws {
        let count = Counter()
        let bodies = Mutex<[Data?]>([])
        let attempt = Mutex(0)
        let session = MockSession({ (request) throws(URLError) in
            bodies.withLock { $0.append(request.httpBody) }
            let status = attempt.withLock { attempt in attempt += 1; return attempt < 3 ? 503 : 200 }
            return (json(ResponseMock(id: "ok", value: 1)), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: RequestConfig(retry: .linear(delay: .zero, maxAttempts: 2)),
            api: APIRequest(method: .post, host: "https://base-url.com", path: "/a", body: .json(CountingBody(count: count)))
        )

        _ = try await endpoint.data()

        #expect(count.value.withLock { $0 } == 1)
        let sent = bodies.withLock { $0 }
        #expect(sent.count == 3)
        #expect(Set(sent.map { $0 }).count == 1)
        #expect(sent.first??.isEmpty == false)
    }
}

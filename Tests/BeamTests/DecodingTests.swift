//
//  DecodingTests.swift
//  Beam
//
//  How a route's body is decoded is chosen by the compiler from the types it declares
//  (`_Route.decoder()` overloads). A type that can't be decoded doesn't compile, so
//  those cases are covered by the overload set itself, not here.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

/// snake_case JSON keys: tells the API's JSON settings apart from Apple's defaults.
extension JSONCoding {
    static var snakeCase: JSONCoding { JSONCoding(keyDecoding: .convertFromSnakeCase) }
}

struct DatedItem: Codable, Sendable, Equatable {
    let createdAt: Date
}

struct SnakeItem: Codable, Sendable, Equatable {
    let userId: String
}

@API(host: "https://base-url.com", config: RequestConfig(json: .snakeCase))
protocol DecodingAPI {
    @Get("/json")
    func json() async throws(APIError<ResponseMock>) -> SnakeItem

    @Get("/text")
    func text() async throws(APIError<Void>) -> String

    @Get("/raw")
    func raw() async throws(APIError<Void>) -> Data

    @Get("/flag")
    func flag() async throws(APIError<Void>) -> Bool

    @Delete("/nothing")
    func nothing() async throws(APIError<Void>)

    @Get("/file", task: .download)
    func file() async throws(APIError<Void>) -> URL

    @Get("/lines", task: .bytes)
    func lines() async throws(APIError<Void>) -> ByteStream<SnakeItem>

    @Post("/raw-body")
    func sendRaw(body: Data) async throws(APIError<Void>)

    @Post("/text-body")
    func sendText(body: String) async throws(APIError<Void>)

    /// Replaces the API's JSON settings: ISO 8601 dates, and no snake_case keys.
    @Get("/dated", json: .iso8601)
    func dated() async throws(APIError<Void>) -> DatedItem

    @Post("/dated", json: .iso8601)
    func sendDated(body: DatedItem) async throws(APIError<Void>)
}

@Suite
struct DecodingTests {
    /// A session answering every request with `body` and `status`, recording the requests.
    private final class Recorder: Sendable {
        let requests = Mutex<[URLRequest]>([])
        var last: URLRequest? { requests.withLock { $0.last } }
    }

    private func session(_ body: String, status: Int = 200, recorder: Recorder = Recorder()) -> MockSession {
        MockSession({ (request) throws(URLError) in
            recorder.requests.withLock { $0.append(request) }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
    }

    // MARK: - Choosing the decoder from the type

    @Test
    func aDecodableTypeIsJSONWithTheAPIsSettings() async throws {
        let api = DecodingAPIClient(session: session(#"{"user_id":"a"}"#))
        #expect(try await api.json() == SnakeItem(userId: "a"))
    }

    @Test
    func stringIsTheTextAsItIs() async throws {
        let api = DecodingAPIClient(session: session("plain text, not JSON"))
        #expect(try await api.text() == "plain text, not JSON")
    }

    @Test
    func dataIsTheRawBody() async throws {
        let api = DecodingAPIClient(session: session("raw"))
        #expect(try await api.raw() == Data("raw".utf8))
    }

    @Test
    func boolIsJSON() async throws {
        let api = DecodingAPIClient(session: session("true"))
        #expect(try await api.flag() == true)
    }

    @Test
    func voidIgnoresTheBody() async throws {
        let api = DecodingAPIClient(session: session("anything"))
        try await api.nothing()
    }

    @Test
    func streamElementsUseTheAPIsSettings() async throws {
        let api = DecodingAPIClient(session: session("{\"user_id\":\"a\"}\n{\"user_id\":\"b\"}\n"))
        var items: [SnakeItem] = []
        for try await item in try await api.lines().jsonLines() { items.append(item) }
        #expect(items == [SnakeItem(userId: "a"), SnakeItem(userId: "b")])
    }

    // MARK: - JSON settings per route

    @Test
    func aRoutesJSONSettingsDecodeItsResponse() async throws {
        let api = DecodingAPIClient(session: session(#"{"createdAt":"2026-05-30T23:20:00Z"}"#))
        #expect(try await api.dated() == DatedItem(createdAt: Date(timeIntervalSince1970: 1780183200)))
    }

    @Test
    func aRoutesJSONSettingsEncodeItsBody() async throws {
        let recorder = Recorder()
        let api = DecodingAPIClient(session: session("", recorder: recorder))

        try await api.sendDated(body: DatedItem(createdAt: Date(timeIntervalSince1970: 1780183200)))
        let sent = try #require(recorder.last?.httpBody)
        #expect(String(decoding: sent, as: UTF8.self) == #"{"createdAt":"2026-05-30T23:20:00Z"}"#)
    }

    /// `json:` replaces the API's settings as a whole: the API's snake_case keys don't apply.
    @Test
    func aRoutesJSONSettingsReplaceTheAPIsWhole() async {
        let api = DecodingAPIClient(session: session(#"{"created_at":"2026-05-30T23:20:00Z"}"#))
        do {
            _ = try await api.dated()
            Issue.record("Expected a decoding error")
        } catch {
            guard case .coding = error else {
                Issue.record("Expected .coding, got \(error)")
                return
            }
        }
    }

    // MARK: - Accept

    @Test
    func theAcceptHeaderComesFromTheDecoder() async throws {
        let recorder = Recorder()
        let api = DecodingAPIClient(session: session(#"{"user_id":"a"}"#, recorder: recorder))

        _ = try await api.json()
        #expect(recorder.last?.value(forHTTPHeaderField: "Accept") == ContentType.json.value)
        _ = try? await api.text()
        #expect(recorder.last?.value(forHTTPHeaderField: "Accept") == ContentType.text.value)
        try? await api.nothing()
        #expect(recorder.last?.value(forHTTPHeaderField: "Accept") == nil)
        // A download isn't decoded: it doesn't ask for JSON.
        if let file = try? await api.file() { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(recorder.last?.value(forHTTPHeaderField: "Accept") == nil)
    }

    // MARK: - Request bodies

    @Test
    func dataAndStringBodiesAreSentAsTheyAre() async throws {
        let recorder = Recorder()
        let api = DecodingAPIClient(session: session("", recorder: recorder))

        try await api.sendRaw(body: Data([0x01, 0x02]))
        #expect(recorder.last?.httpBody == Data([0x01, 0x02]))
        #expect(recorder.last?.value(forHTTPHeaderField: "Content-Type") == ContentType.data.value)

        try await api.sendText(body: "hola")
        #expect(recorder.last?.httpBody == Data("hola".utf8))
        #expect(recorder.last?.value(forHTTPHeaderField: "Content-Type") == ContentType.text.value)
    }

    // MARK: - Error bodies

    @Test
    func anErrorBodyIsDecodedWithTheRoutesErrorType() async {
        let api = DecodingAPIClient(session: session(#"{"id":"E1","value":7}"#, status: 422))
        do {
            _ = try await api.json()
            Issue.record("Expected an HTTP error")
        } catch {
            #expect(error == .http(status: .unprocessableEntity))
            #expect(error.body == ResponseMock(id: "E1", value: 7))
        }
    }

    @Test
    func anErrorBodyInAnotherFormatLeavesTheErrorWithoutBody() async {
        let api = DecodingAPIClient(session: session("<html>Bad gateway</html>", status: 502))
        do {
            _ = try await api.json()
            Issue.record("Expected an HTTP error")
        } catch {
            #expect(error == .http(status: .badGateway))
            #expect(error.body == nil)
            // The server's answer is still there, with why it didn't decode.
            #expect(error.rawBody == Data("<html>Bad gateway</html>".utf8))
            guard case .http(_, let body, _) = error else { return }
            #expect(body.text == "<html>Bad gateway</html>")
            #expect(body.decodingError != nil)
        }
    }

    @Test
    func aDecodedErrorBodyKeepsItsRawBodyToo() async {
        let api = DecodingAPIClient(session: session(#"{"id":"E1","value":7}"#, status: 422))
        do {
            _ = try await api.json()
            Issue.record("Expected an HTTP error")
        } catch {
            #expect(error.body?.id == "E1")
            #expect(error.rawBody == Data(#"{"id":"E1","value":7}"#.utf8))
            // Monitors get the error without its type, but with the raw body.
            #expect(error.asVoid.rawBody == error.rawBody)
        }
    }

    @Test
    func aDownloadsErrorBodyIsReadOnlyUpToItsLimit() async {
        let big = String(repeating: "x", count: HTTPErrorBody<Void>.limit * 3)
        let api = DecodingAPIClient(session: session(big, status: 500))
        do {
            _ = try await api.file()
            Issue.record("Expected an HTTP error")
        } catch {
            #expect(error.rawBody?.count == HTTPErrorBody<Void>.limit)
        }
    }

    @Test
    func anUndecodedErrorBodyIsAWarning() {
        let event = LogEvent.undecodedErrorBody(id: "a1", type: "ErrorDto", detail: "keyNotFound code")
        #expect(event.meta.level == .warning)
        #expect(event.rendered(bodies: false).contains("ErrorDto"))
    }
}

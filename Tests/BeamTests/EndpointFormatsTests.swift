//
//  EndpointFormatsTests.swift
//  Beam
//
//  An endpoint reads its bodies by their types, as `@API` does: `String` is text,
//  `Data` the raw bytes, another `Decodable` JSON, `Void` nothing, and a
//  `BodyRepresentable` type reads itself.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Fixtures

/// Answers every request with `status` and `body`, keeping the requests.
private final class Answering: Sendable {
    private let requests = Mutex<[URLRequest]>([])
    var last: URLRequest? { requests.withLock { $0.last } }

    func session(_ body: String, status: Int = 200) -> MockSession {
        MockSession({ [self] (request) throws(URLError) in
            requests.withLock { $0.append(request) }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
    }
}

private func makeAPI(_ session: MockSession) -> APIConfiguration {
    APIConfiguration(host: "https://api.example.com", session: session, config: RequestConfig(retry: .none))
}

private struct Problem: Codable, Equatable, Sendable {
    let code: String
}

/// A body type that isn't Decodable: its text, reversed.
private struct Reversed: BodyRepresentable, Equatable {
    let text: String
    static var bodyContentType: ContentType? { "text/reversed" }
    static func decodeBody(_ data: Data) throws(CodingError) -> Reversed {
        guard let text = String(data: data, encoding: .utf8) else { throw .typeMismatch }
        return Reversed(text: String(text.reversed()))
    }
}

// MARK: - Tests

@Suite
struct EndpointFormatsTests {

    @Test
    func aStringIsReadAsText() async throws {
        let server = Answering()
        let api = makeAPI(server.session("hola"))
        let text = try await Endpoint<String, Void>(api, request: api.request(.get, "/a")).data()

        #expect(text == "hola")
        #expect(server.last?.value(forHTTPHeaderField: "Accept") == ContentType.text.value)
    }

    @Test
    func dataIsReadAsTheRawBytes() async throws {
        let server = Answering()
        let api = makeAPI(server.session("{not json"))
        let bytes = try await Endpoint<Data, Void>(api, request: api.request(.get, "/a")).data()

        #expect(bytes == Data("{not json".utf8))
    }

    @Test
    func anotherDecodableIsReadAsJSON() async throws {
        let server = Answering()
        let api = makeAPI(server.session(#"{"id":"1","value":2}"#))
        let value = try await Endpoint<ResponseMock, Void>(api, request: api.request(.get, "/a")).data()

        #expect(value == ResponseMock(id: "1", value: 2))
        #expect(server.last?.value(forHTTPHeaderField: "Accept") == ContentType.json.value)
    }

    @Test
    func voidReadsNothing() async throws {
        let server = Answering()
        let api = makeAPI(server.session("anything"))
        try await Endpoint<Void, Void>(api, request: api.request(.get, "/a")).data()

        #expect(server.last?.value(forHTTPHeaderField: "Accept") == nil)
    }

    @Test
    func aBodyRepresentableTypeReadsItself() async throws {
        let server = Answering()
        let api = makeAPI(server.session("aloh"))
        let value = try await Endpoint<Reversed, Void>(api, request: api.request(.get, "/a")).data()

        #expect(value == Reversed(text: "hola"))
        #expect(server.last?.value(forHTTPHeaderField: "Accept") == "text/reversed")
    }

    // MARK: Error bodies

    @Test
    func aDecodableErrorBodyIsReadAsJSON() async {
        let server = Answering()
        let api = makeAPI(server.session(#"{"code":"E42"}"#, status: 422))
        do {
            try await Endpoint<Void, Problem>(api, request: api.request(.get, "/a")).data()
            Issue.record("Expected an HTTP error")
        } catch {
            #expect(error.body == Problem(code: "E42"))
        }
    }

    @Test
    func aStringErrorBodyIsReadAsText() async {
        let server = Answering()
        let api = makeAPI(server.session("Bad gateway", status: 500))
        do {
            _ = try await Endpoint<ResponseMock, String>(api, request: api.request(.get, "/a")).data()
            Issue.record("Expected an HTTP error")
        } catch {
            #expect(error.body == "Bad gateway")
        }
    }

    @Test
    func aBodyRepresentableErrorBodyReadsItself() async {
        let server = Answering()
        let api = makeAPI(server.session("olleh", status: 400))
        do {
            try await Endpoint<Void, Reversed>(api, request: api.request(.get, "/a")).data()
            Issue.record("Expected an HTTP error")
        } catch {
            #expect(error.body == Reversed(text: "hello"))
        }
    }

    // MARK: Formats of your own

    @Test
    func explicitDecodersReplaceTheTypesFormats() async throws {
        let server = Answering()
        let api = makeAPI(server.session("a,b,c"))
        let csv = BodyDecoder<[String]>(accept: .csv) { (data, _) throws(CodingError) in
            String(decoding: data, as: UTF8.self).split(separator: ",").map(String.init)
        }
        let values = try await Endpoint(api, request: api.request(.get, "/a"), response: csv, error: .void).data()

        #expect(values == ["a", "b", "c"])
        #expect(server.last?.value(forHTTPHeaderField: "Accept") == "text/csv")
    }
}

//
//  APIConfigurationTests.swift
//  Beam
//
//  An API declared by hand: `APIConfiguration`, its request builders and `Endpoint`.
//

import Foundation
import Testing
@testable import Beam

@Suite
struct APIConfigurationTests {
    private let api = APIConfiguration(host: "https://api.example.com", base: "/v1", headers: ["X-App": "1"])

    // MARK: - Route requests

    @Test
    func aRouteRequestFillsItsPlaceholdersAndKeepsTheTemplate() throws {
        let request = api.request(.get, "/users/{id}/files", values: ["id": "a/b"])

        #expect(request.path == "/v1/users/a/b/files")
        #expect(request.pathTemplate == "/v1/users/{id}/files")
        // The value is one segment: its `/` stays escaped.
        #expect(try #require(request.url).absoluteString == "https://api.example.com/v1/users/a%2Fb/files")
    }

    @Test
    func aRouteRequestHasTheAPIHeadersUnlessGivenOthers() {
        #expect(api.request(.get, "/a").headers == ["X-App": "1"])
        #expect(api.request(.get, "/a", headers: ["X-Other": "2"]).headers == ["X-Other": "2"])
    }

    @Test
    func aRouteRequestCarriesItsQueryAndBody() throws {
        let request = api.request(.post, "/a", query: [URLQueryItem(name: "page", value: "2")], body: .json(UploadRequestMock(content: "x")))

        #expect(try #require(request.url).absoluteString == "https://api.example.com/v1/a?page=2")
        #expect(request.body != nil)
    }

    // MARK: - Absolute URLs

    @Test
    func anAbsoluteURLIsTheTargetAndTheRouteItsTemplate() throws {
        let url = URL(string: "https://cdn.example.com/files/abc?sig=1")!
        let request = api.request(.get, url: url, route: "DocumentsAPI.download")

        #expect(try #require(request.url) == url)
        #expect(request.pathTemplate == "DocumentsAPI.download")
        #expect(request.headers == ["X-App": "1"])
    }

    // MARK: - Endpoint

    @Test
    func anEndpointUsesTheAPIConfigurationUnlessGivenItsOwn() {
        let api = APIConfiguration(host: "https://api.example.com", config: RequestConfig(retry: .none))
        let request = api.request(.get, "/a")

        #expect(Endpoint<ResponseMock, Void>(api, request: request).config.retry.maxAttempts == 0)
        #expect(Endpoint<ResponseMock, Void>(api, config: .standard, request: request).config.retry.maxAttempts == RequestConfig.standard.retry.maxAttempts)
    }

    @Test
    func anEndpointByHandSendsItsRequestThroughTheAPIServices() async throws {
        let recorder = Recorder()
        let session = MockSession({ (request) throws(URLError) in
            recorder.record(request)
            return (Data(#"{"id":"1","value":1}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let api = APIConfiguration(host: "https://api.example.com", base: "/v1", headers: ["X-App": "1"], session: session)
        let endpoint = Endpoint<ResponseMock, Void>(api, request: api.request(.get, "/users/{id}", values: ["id": "7"]))

        let user = try await endpoint.data()

        #expect(user.id == "1")
        let sent = try #require(recorder.requests.first)
        #expect(sent.url?.absoluteString == "https://api.example.com/v1/users/7")
        #expect(sent.value(forHTTPHeaderField: "X-App") == "1")
    }
}

/// Keeps the requests a session receives.
private final class Recorder: Sendable {
    private let storage = Mutex<[URLRequest]>([])
    var requests: [URLRequest] { storage.withLock { $0 } }
    func record(_ request: URLRequest) { storage.withLock { $0.append(request) } }
}

import Synchronization

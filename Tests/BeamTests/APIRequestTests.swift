//
//  APIRequestTests.swift
//  Beam
//
//  Tests for URL construction, empty paths, query params, and optional handling.
//

import Foundation
import Testing
@testable import Beam

@Suite
struct APIRequestTests {

    // MARK: - URL Construction

    @Test
    func urlWithHostAndPath() {
        let request = APIRequest(method: .get, host: "https://api.example.com", path: "/users/42")
        #expect(request.url?.absoluteString == "https://api.example.com/users/42")
    }

    @Test
    func urlWithHostBaseAndPath() {
        let request = APIRequest(method: .get, host: "https://api.example.com/v2", path: "/users")
        #expect(request.url?.absoluteString == "https://api.example.com/v2/users")
    }

    @Test
    func urlWithEmptyPath() {
        let request = APIRequest(method: .get, host: "https://api.example.com/v2/schedules", path: "")
        #expect(request.url?.absoluteString == "https://api.example.com/v2/schedules")
    }

    @Test
    func urlWithQueryParams() {
        let request = APIRequest(
            method: .get,
            host: "https://api.example.com",
            path: "/search",
            query: [URLQueryItem(name: "q", value: "swift"), URLQueryItem(name: "page", value: "1")]
        )
        let url = request.url!
        #expect(url.absoluteString.contains("q=swift"))
        #expect(url.absoluteString.contains("page=1"))
    }

    @Test
    func urlWithEmptyParamsHasNoQueryString() {
        let request = APIRequest(method: .get, host: "https://api.example.com", path: "/users")
        #expect(request.url?.absoluteString == "https://api.example.com/users")
        #expect(!request.url!.absoluteString.contains("?"))
    }

    @Test
    func urlWithInvalidHostReturnsNil() {
        // A host with spaces that URLComponents rejects
        let request = APIRequest(method: .get, host: "ht tp://bad", path: "/users")
        #expect(request.url == nil)
    }

    @Test
    func urlWithPathParamsInterpolated() {
        let id = 42
        let request = APIRequest(method: .get, host: "https://api.example.com", path: "/users/\(id)")
        #expect(request.url?.absoluteString == "https://api.example.com/users/42")
    }

    @Test
    func urlWithHostTrailingSlashAndPath() {
        let request = APIRequest(method: .get, host: "https://api.example.com/", path: "/users")
        // URLComponents handles this gracefully
        #expect(request.url?.path().contains("users") == true)
    }

    // MARK: - Content Headers

    @Test
    func contentHeadersForJSON() {
        let request = APIRequest(method: .post, host: "https://api.example.com", path: "/users", body: .json("test"))
        #expect(request.contentHeaders["Content-Type"]?.contains("application/json") == true)
    }

    @Test
    func contentHeadersForMultipart() {
        let form = MultipartForm(media: [])
        let request = APIRequest(method: .post, host: "https://api.example.com", path: "/upload", body: .multipart(form))
        #expect(request.contentHeaders["Content-Type"]?.contains("multipart/form-data") == true)
    }

    @Test
    func contentHeadersForRawData() {
        let request = APIRequest(method: .post, host: "https://api.example.com", path: "/raw", body: .data(Data()))
        #expect(request.contentHeaders["Content-Type"]?.contains("application/octet-stream") == true)
    }

    @Test
    func noBodyNoContentHeaders() {
        let request = APIRequest(method: .get, host: "https://api.example.com", path: "/users")
        #expect(request.contentHeaders.isEmpty)
    }
}

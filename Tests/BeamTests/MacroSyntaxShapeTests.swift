//
//  MacroSyntaxShapeTests.swift
//  Beam
//
//  End-to-end checks that `@API` recognises equivalent spellings of the types and
//  attributes it gives meaning to, and that the new `@API` configuration
//  arguments (`config`, `interceptors`, `logLevel`) reach every request.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Equivalent spellings

@API(host: "https://base-url.com", base: "/v1")
protocol SpellingsAPI {
    /// `Optional<Int>` is optional: omitted when nil (it used to be sent as `page=nil`).
    @Get("/search")
    func search(query term: String, query page: Optional<Int>) async throws(APIError<Void>) -> [ResponseMock]

    /// `Array<Foundation.URLQueryItem>` is the query-items array.
    @Get("/items")
    func items(params: Array<Foundation.URLQueryItem>) async throws(APIError<Void>) -> [ResponseMock]

    /// `Foundation.URL` labelled `url` is the absolute-URL override.
    @Get
    func follow(url: Foundation.URL) async throws(APIError<Void>) -> ResponseMock

    /// Module-qualified route attribute and thrown error type.
    @Beam.Post("/qualified")
    func qualified(body: ResponseMock) async throws(Beam.APIError<Void>) -> ResponseMock

    /// Optional body: `nil` sends no body instead of encoding `null`.
    @Put("/optional-body")
    func update(body: ResponseMock?) async throws(APIError<Void>)

    /// Explicit task kind spelling.
    @Get("/file", task: _TaskKind.download)
    func file() async throws(APIError<Void>) -> URL

    /// Parameters without a label: the client keeps them without one, also in the
    /// transfer routes' helpers and overloads.
    @Get("/unlabeled")
    func unlabeled(_ items: [URLQueryItem]) async throws(APIError<Void>) -> ResponseMock

    @Post("/unlabeled-upload", task: .upload)
    func unlabeledUpload(_ items: [URLQueryItem], body: ResponseMock) async throws(APIError<Void>) -> ResponseMock

    @Get("/unlabeled-download", task: .download)
    func unlabeledDownload(_ items: [URLQueryItem]) async throws(APIError<Void>) -> URL

    /// The escapes documented in `@API`: a query item named "body", a `{url}` placeholder.
    @Get("/escapes")
    func queryNamedBody(query body: String) async throws(APIError<Void>) -> ResponseMock

    @Get("/links/{url}")
    func link(url: String) async throws(APIError<Void>) -> ResponseMock
}

// MARK: - Shapes resolved by the type checker

typealias ShapeParams = [URLQueryItem]
typealias ShapeError = APIError<Void>
typealias ShapeChunks = ByteStream<ResponseMock>

enum ShapeKind: String, Sendable { case premium = "PREMIUM" }

@API(host: "https://base-url.com")
protocol TypeShapesAPI {
    /// Typealias of `[URLQueryItem]`: only the type checker can see through it.
    @Get("/alias")
    func alias(params: ShapeParams) async throws(APIError<Void>) -> ResponseMock

    /// Optional query items: omitted when nil.
    @Get("/maybe-items")
    func maybeItems(params: [URLQueryItem]?) async throws(APIError<Void>) -> ResponseMock

    /// Query items under a `query` label are used as they are (they used to be sent as `items=[…]`).
    @Get("/labelled-items")
    func labelledItems(query items: [URLQueryItem]) async throws(APIError<Void>) -> ResponseMock

    /// Optional header: omitted when nil (this used not to compile).
    @Get("/header")
    func optionalHeader(header token: String?) async throws(APIError<Void>) -> ResponseMock

    /// Raw-value enums use their raw value in path, query and header.
    @Get("/kinds/{kind}")
    func kind(kind: ShapeKind, query filter: ShapeKind, header mode: ShapeKind) async throws(APIError<Void>) -> ResponseMock

    /// Arrays in a named query repeat the key, once per value.
    @Get("/arrays")
    func arrays(query id: [Int], query kind: [ShapeKind]?) async throws(APIError<Void>) -> ResponseMock
    /// Implicitly unwrapped optional (this used not to compile).
    @Get("/iuo")
    func iuo(query page: Int!) async throws(APIError<Void>) -> ResponseMock

    /// Typealias of the thrown error type.
    @Get("/alias-error")
    func aliasError() async throws(ShapeError) -> ResponseMock

    /// Placeholder matched by the external label; the body uses the internal name.
    @Get("/users/{id}")
    func user(id identifier: Int) async throws(APIError<Void>) -> ResponseMock

    /// Absolute URL with a different internal name (this used to reference `url`).
    @Get
    func follow(url target: URL) async throws(APIError<Void>) -> ResponseMock

    /// Typealias of `ByteStream<T>`: the element type is inferred, not parsed.
    @Get("/stream", task: .bytes)
    func stream() async throws(APIError<Void>) -> ShapeChunks
}

// MARK: - Headers evaluated per request

/// Stands in for app state that changes at runtime (the signed-in user).
private enum LiveHeaders {
    static let userID = Mutex(-1)
    static var current: [String: String] { ["Device-Info-Wid": "\(userID.withLock { $0 })"] }
}

@API(host: "https://base-url.com", headers: LiveHeaders.current)
protocol LiveHeadersAPI {
    @Get("/me")
    func me() async throws(APIError<Void>) -> ResponseMock
}

/// Stands in for an environment that changes at runtime (e.g. a debug menu switch).
private enum LiveLocation {
    static let current = Mutex((host: "https://one.com", base: "/v1"))
    static var host: String { current.withLock { $0.host } }
    static var base: String { current.withLock { $0.base } }
}

@API(host: LiveLocation.host, base: LiveLocation.base)
protocol LiveLocationAPI {
    @Get("/users/{id}")
    func user(id: Int) async throws(APIError<Void>) -> ResponseMock
}

// MARK: - @API configuration

/// Adds a header to every request and counts the responses it sees.
private final class StampInterceptor: Interceptor {
    /// Responses seen, by request id: tests sharing the interceptor run in parallel.
    let responses = Mutex<[String: Int]>([:])

    func intercept(request: URLRequest, context: EndpointContext) async throws(InterceptorError) -> URLRequest {
        var request = request
        request.setValue("stamped", forHTTPHeaderField: "X-Stamp")
        return request
    }

    func intercept(response: Response, context: EndpointContext) async throws(InterceptorError) -> Response {
        responses.withLock { $0[response.http.value(forHTTPHeaderField: "X-Test-ID") ?? "", default: 0] += 1 }
        return response
    }
}

private let stamp = StampInterceptor()

@API(
    host: "https://base-url.com",
    config: RequestConfig(retry: .none, timeout: .seconds(7)),
    interceptors: [stamp],
    logLevel: .error
)
protocol ConfiguredAPI {
    @Get("/plain")
    func plain() async throws(APIError<Void>) -> ResponseMock

    /// Route arguments still override the API-level config.
    @Get("/override", timeout: .seconds(2), retry: .standard)
    func override() async throws(APIError<Void>) -> ResponseMock
}

// MARK: - Tests

@Suite
struct MacroSyntaxShapeTests {

    private static let okBody = try! JSONEncoder().encode([ResponseMock(id: "1", value: 1)])
    private static let okSingle = try! JSONEncoder().encode(ResponseMock(id: "1", value: 1))

    private func ok(_ request: URLRequest, _ body: Data) -> (Data, URLResponse) {
        (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    @Test
    func optionalGenericQueryIsOmittedWhenNil() async throws {
        let session = MockSession({ [self] (request) throws(URLError) in
            let query = request.url?.query() ?? ""
            #expect(query == "term=swift")
            return ok(request, Self.okBody)
        })
        _ = try await SpellingsAPIClient(session: session).search(query: "swift", query: nil)
    }

    @Test
    func optionalGenericQueryIsSentWhenPresent() async throws {
        let session = MockSession({ [self] (request) throws(URLError) in
            #expect(request.url?.query() == "term=swift&page=2")
            return ok(request, Self.okBody)
        })
        _ = try await SpellingsAPIClient(session: session).search(query: "swift", query: 2)
    }

    @Test
    func genericArrayOfQueryItemsIsUsedAsQuery() async throws {
        let session = MockSession({ [self] (request) throws(URLError) in
            #expect(request.url?.query() == "a=1&b=2")
            return ok(request, Self.okBody)
        })
        _ = try await SpellingsAPIClient(session: session).items(params: [.init(name: "a", value: "1"), .init(name: "b", value: "2")])
    }

    @Test
    func unlabeledParametersKeepNoLabel() async throws {
        let session = MockSession({ [self] (request) throws(URLError) in
            #expect(request.url?.query() == "a=1")
            return ok(request, json(ResponseMock(id: "1", value: 1)))
        })
        let api = SpellingsAPIClient(session: session)
        let items = [URLQueryItem(name: "a", value: "1")]
        _ = try await api.unlabeled(items)
        _ = try await api.unlabeledUpload(items, body: ResponseMock(id: "1", value: 1))
        _ = try await api.unlabeledUploadTask(items, body: ResponseMock(id: "1", value: 1)).start()
    }

    @Test
    func theDocumentedEscapesWork() async throws {
        let recorder = Mutex<[URL]>([])
        let session = MockSession({ [self] (request) throws(URLError) in
            recorder.withLock { $0.append(request.url!) }
            return ok(request, json(ResponseMock(id: "1", value: 1)))
        })
        let api = SpellingsAPIClient(session: session)
        _ = try await api.queryNamedBody(query: "x")
        _ = try await api.link(url: "a b")
        let urls = recorder.withLock { $0 }
        #expect(urls.first?.query() == "body=x")
        #expect(urls.last?.path().hasSuffix("/links/a%20b") == true)
    }

    @Test
    func qualifiedURLIsTheAbsoluteTarget() async throws {
        let session = MockSession({ [self] (request) throws(URLError) in
            #expect(request.url?.absoluteString == "https://elsewhere.com/next?page=3")
            return ok(request, Self.okSingle)
        })
        _ = try await SpellingsAPIClient(session: session).follow(url: URL(string: "https://elsewhere.com/next?page=3")!)
    }

    @Test
    func qualifiedAttributeAndErrorTypeAreRecognised() async throws {
        let session = MockSession({ [self] (request) throws(URLError) in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path() == "/v1/qualified")
            #expect(request.httpBody != nil)
            return ok(request, Self.okSingle)
        })
        let result = try await SpellingsAPIClient(session: session).qualified(body: ResponseMock(id: "1", value: 1))
        #expect(result.id == "1")
    }

    @Test
    func optionalBodyIsOmittedWhenNilAndEncodedWhenPresent() async throws {
        let bodies = Mutex<[Data?]>([])
        let session = MockSession({ [self] (request) throws(URLError) in
            bodies.withLock { $0.append(request.httpBody) }
            return ok(request, Data())
        })
        let api = SpellingsAPIClient(session: session)
        try await api.update(body: nil)
        try await api.update(body: ResponseMock(id: "2", value: 2))

        let sent = bodies.withLock { $0 }
        #expect(sent.count == 2)
        #expect(sent.first.flatMap { $0 } == nil)
        let decoded = try sent.last.flatMap { $0 }.map { try JSONDecoder().decode(ResponseMock.self, from: $0) }
        #expect(decoded == ResponseMock(id: "2", value: 2))
    }

    @Test
    func explicitTaskKindSpellingSelectsDownload() async throws {
        let session = MockSession({ [self] (request) throws(URLError) in ok(request, Data("file".utf8)) })
        let url = try await SpellingsAPIClient(session: session).file()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Data(contentsOf: url) == Data("file".utf8))
    }

    // MARK: - Shapes resolved by the type checker

    /// Records the last request and answers with a single `ResponseMock`.
    private final class Recorder: Sendable {
        private final class Storage: Sendable {
            let last = Mutex<URLRequest?>(nil)
        }

        private let storage = Storage()
        var request: URLRequest? { storage.last.withLock { $0 } }

        func session() -> MockSession {
            MockSession({ [storage] (request) throws(URLError) in
                storage.last.withLock { $0 = request }
                let body = json(ResponseMock(id: "1", value: 1))
                return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        }
    }

    @Test
    func typealiasOfQueryItemsIsTheQuery() async throws {
        let recorder = Recorder()
        _ = try await TypeShapesAPIClient(session: recorder.session()).alias(params: [.init(name: "a", value: "1")])
        #expect(recorder.request?.url?.query() == "a=1")
    }

    @Test
    func optionalQueryItemsAreOmittedWhenNil() async throws {
        let recorder = Recorder()
        let api = TypeShapesAPIClient(session: recorder.session())

        _ = try await api.maybeItems(params: nil)
        #expect(recorder.request?.url?.query() == nil)

        _ = try await api.maybeItems(params: [.init(name: "b", value: "2")])
        #expect(recorder.request?.url?.query() == "b=2")
    }

    @Test
    func queryItemsUnderAQueryLabelAreUsedAsTheyAre() async throws {
        let recorder = Recorder()
        _ = try await TypeShapesAPIClient(session: recorder.session()).labelledItems(query: [.init(name: "c", value: "3")])
        #expect(recorder.request?.url?.query() == "c=3")
    }

    /// An array repeats the key in order; an empty or `nil` one adds nothing.
    @Test
    func anArrayInAQueryRepeatsTheKey() async throws {
        let recorder = Recorder()
        let api = TypeShapesAPIClient(session: recorder.session())
        _ = try await api.arrays(query: [28, 8], query: [.premium])
        #expect(recorder.request?.url?.query() == "id=28&id=8&kind=PREMIUM")
        _ = try await api.arrays(query: [1], query: nil)
        #expect(recorder.request?.url?.query() == "id=1")
        _ = try await api.arrays(query: [], query: nil)
        #expect(recorder.request?.url?.query() == nil)
    }

    @Test
    func optionalHeaderIsOmittedWhenNil() async throws {
        let recorder = Recorder()
        let api = TypeShapesAPIClient(session: recorder.session())

        _ = try await api.optionalHeader(header: nil)
        #expect(recorder.request?.value(forHTTPHeaderField: "token") == nil)

        _ = try await api.optionalHeader(header: "abc")
        #expect(recorder.request?.value(forHTTPHeaderField: "token") == "abc")
    }

    @Test
    func rawValueEnumsUseTheirRawValue() async throws {
        let recorder = Recorder()
        _ = try await TypeShapesAPIClient(session: recorder.session()).kind(kind: .premium, query: .premium, header: .premium)
        #expect(recorder.request?.url?.path() == "/kinds/PREMIUM")
        #expect(recorder.request?.url?.query() == "filter=PREMIUM")
        #expect(recorder.request?.value(forHTTPHeaderField: "mode") == "PREMIUM")
    }

    @Test
    func implicitlyUnwrappedQueryBehavesAsOptional() async throws {
        let recorder = Recorder()
        let api = TypeShapesAPIClient(session: recorder.session())

        _ = try await api.iuo(query: nil)
        #expect(recorder.request?.url?.query() == nil)

        _ = try await api.iuo(query: 4)
        #expect(recorder.request?.url?.query() == "page=4")
    }

    @Test
    func typealiasOfTheThrownErrorWorks() async throws {
        let session = MockSession({ (request) throws(URLError) in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        })
        do {
            _ = try await TypeShapesAPIClient(session: session).aliasError()
            Issue.record("Should have thrown")
        } catch {
            #expect(error.status == .notFound)
        }
    }

    @Test
    func pathPlaceholderMatchedByExternalLabelUsesTheValue() async throws {
        let recorder = Recorder()
        _ = try await TypeShapesAPIClient(session: recorder.session()).user(id: 42)
        #expect(recorder.request?.url?.path() == "/users/42")
    }

    @Test
    func absoluteURLWithADifferentInternalName() async throws {
        let recorder = Recorder()
        _ = try await TypeShapesAPIClient(session: recorder.session()).follow(url: URL(string: "https://elsewhere.com/x")!)
        #expect(recorder.request?.url?.absoluteString == "https://elsewhere.com/x")
    }

    @Test
    func typealiasOfByteStreamInfersItsElementType() async throws {
        let lines = [ResponseMock(id: "a", value: 1), ResponseMock(id: "b", value: 2)]
            .map { String(decoding: json($0), as: UTF8.self) }
            .joined(separator: "\n")
        let session = MockSession({ (request) throws(URLError) in
            (Data(lines.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })

        let stream = try await TypeShapesAPIClient(session: session).stream()
        var ids: [String] = []
        for try await chunk in stream.jsonLines() { ids.append(chunk.id) }
        #expect(ids == ["a", "b"])
    }

    // MARK: - Headers evaluated per request

    /// Regression: the API configuration is built once, and `headers:` used to be
    /// evaluated with it, so values such as the signed-in user's id stayed frozen.
    @Test
    func apiHeadersAreEvaluatedOnEveryRequest() async throws {
        let recorder = Recorder()
        let api = LiveHeadersAPIClient(session: recorder.session())

        LiveHeaders.userID.withLock { $0 = -1 }
        _ = try await api.me()
        #expect(recorder.request?.value(forHTTPHeaderField: "Device-Info-Wid") == "-1")

        LiveHeaders.userID.withLock { $0 = 12345 }
        _ = try await api.me()                                          // same client
        #expect(recorder.request?.value(forHTTPHeaderField: "Device-Info-Wid") == "12345")

        _ = try await LiveHeadersAPIClient(session: recorder.session()).me() // new client
        #expect(recorder.request?.value(forHTTPHeaderField: "Device-Info-Wid") == "12345")
    }

    @Test
    func apiHostAndBaseAreEvaluatedOnEveryRequest() async throws {
        let recorder = Recorder()
        let api = LiveLocationAPIClient(session: recorder.session())

        LiveLocation.current.withLock { $0 = (host: "https://one.com", base: "/v1") }
        _ = try await api.user(id: 1)
        #expect(recorder.request?.url?.absoluteString == "https://one.com/v1/users/1")

        LiveLocation.current.withLock { $0 = (host: "https://two.com", base: "/v2") }
        _ = try await api.user(id: 2)                                       // same client
        #expect(recorder.request?.url?.absoluteString == "https://two.com/v2/users/2")
    }

    @Test
    func routeRequestReadsTheBaseOnceForPathAndTemplate() {
        // Mutex is ~Copyable, so the autoclosure captures it through a class.
        final class Reads: Sendable {
            let count = Mutex(0)
            func next() -> String { count.withLock { $0 += 1; return "/v\($0)" } }
        }
        let reads = Reads()
        let configuration = APIConfiguration(host: "https://base-url.com", base: reads.next())
        let request = configuration.request(.get, "/users/{id}", values: ["id": "7"], headers: [:])
        #expect(request.path == "/v1/users/7")
        #expect(request.pathTemplate == "/v1/users/{id}")
        #expect(reads.count.withLock { $0 } == 1)
    }

    // MARK: - @API configuration

    @Test
    func interceptorsConfigAndLogLevelReachTheConfiguration() {
        let configuration = ConfiguredAPIClient._apiConfiguration
        #expect(configuration.config.retry == .none)
        #expect(configuration.config.timeout == .seconds(7))
        #expect(configuration.interceptors.count == 1)
        #expect(configuration.logLevel == .error)
    }

    @Test
    func apiInterceptorsRunOnEveryRequest() async throws {
        let testID = UUID().uuidString
        let session = MockSession({ (request) throws(URLError) in
            #expect(request.value(forHTTPHeaderField: "X-Stamp") == "stamped")
            #expect(request.timeoutInterval == 7)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["X-Test-ID": testID])!
            return (Self.okSingle, response)
        })
        _ = try await ConfiguredAPIClient(session: session).plain()
        #expect(stamp.responses.withLock { $0[testID] } == 1)
    }

    @Test
    func apiConfigAppliesAndRoutesOverrideIt() async throws {
        let attempts = Mutex<[String: Int]>([:])
        let session = MockSession({ (request) throws(URLError) in
            attempts.withLock { $0[request.url!.path(), default: 0] += 1 }
            if request.url!.path() == "/override" {
                #expect(request.timeoutInterval == 2)
            }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        })
        let api = ConfiguredAPIClient(session: session)
        _ = try? await api.plain()     // API config: retry .none → 1 attempt
        _ = try? await api.override()  // route: retry .standard → 2 attempts

        #expect(attempts.withLock { $0 } == ["/plain": 1, "/override": 2])
    }
}

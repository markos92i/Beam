//
//  MacroTests.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//
//  Expansion-level tests: assert that @API produces the exact client the macro
//  system is contracted to generate. Each test pins one route feature so a
//  regression points straight at what broke. End-to-end behaviour (requests hitting
//  a MockSession) is covered separately by the BeamTests integration suites.
//

import SwiftParser
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import BeamMacros

private let testMacros: [String: Macro.Type] = [
    "API": APIMacro.self,
    "Get": GetMacro.self,
    "Post": PostMacro.self,
    "Put": PutMacro.self,
    "Delete": DeleteMacro.self,
    "Patch": PatchMacro.self,
    "Socket": SocketMacro.self,
]

@Suite
struct MacroExpansionTests {

    // MARK: - Path parameter interpolation

    @Test
    func pathParameterIsInterpolatedAndTemplated() {
        assertMacroExpansion(
            """
            @API(host: "https://api.example.com", base: "/v1")
            protocol API {
                @Get("/users/{id}")
                func fetch(id: Int) async throws(APIError<ErrorDto>) -> UserDto
            }
            """,
            expandedSource: """
            protocol API {
                func fetch(id: Int) async throws(APIError<ErrorDto>) -> UserDto
            }

            // @unchecked Sendable: mock closures are nil in production and thread-safe by design.
            // Assigning mock closures concurrently with active calls is a caller error.
            struct APIClient: API, @unchecked Sendable {
                static let _apiConfiguration = Beam::APIConfiguration(
                    host: "https://api.example.com",
                    base: "/v1",
                    headers: [:]
                )

                private let _config: Beam::APIConfiguration

                init(session: (any Beam::SessionProtocol)? = nil) {
                    _config = Self._apiConfiguration.replacing(session: session)
                }
                var onFetch: ((Int) async throws(APIError<ErrorDto>) -> UserDto)?

                func fetch(id: Int) async throws(APIError<ErrorDto>) -> UserDto {
                    let endpoint = Beam::Endpoint<UserDto, APIError<ErrorDto>._Failure>(
                            _config,
                            request: _config._request(.get, "/users/{id}", values: ["id": Beam::_Route.path(id)])
                        ).mocking(onFetch.map { mock in
                            .init(_unchecked: { (_) async throws(APIError<ErrorDto>) in
                                    return try await mock(id)
                                })
                        })
                    return try await endpoint.data()
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - JSON body

    @Test
    func bodyParameterIsEncodedAsJSON() {
        assertMacroExpansion(
            """
            @API(host: "https://api.example.com")
            protocol API {
                @Post("/users")
                func create(body: CreateUserRequest) async throws(APIError<ErrorDto>) -> UserDto
            }
            """,
            expandedSource: """
            protocol API {
                func create(body: CreateUserRequest) async throws(APIError<ErrorDto>) -> UserDto
            }

            // @unchecked Sendable: mock closures are nil in production and thread-safe by design.
            // Assigning mock closures concurrently with active calls is a caller error.
            struct APIClient: API, @unchecked Sendable {
                static let _apiConfiguration = Beam::APIConfiguration(
                    host: "https://api.example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: Beam::APIConfiguration

                init(session: (any Beam::SessionProtocol)? = nil) {
                    _config = Self._apiConfiguration.replacing(session: session)
                }
                var onCreate: ((CreateUserRequest) async throws(APIError<ErrorDto>) -> UserDto)?

                func create(body: CreateUserRequest) async throws(APIError<ErrorDto>) -> UserDto {
                    let endpoint = Beam::Endpoint<UserDto, APIError<ErrorDto>._Failure>(
                            _config,
                            request: _config._request(.post, "/users", body: Beam::_Route.body(body))
                        ).mocking(onCreate.map { mock in
                            .init(_unchecked: { (_) async throws(APIError<ErrorDto>) in
                                    return try await mock(body)
                                })
                        })
                    return try await endpoint.data()
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Optional named query parameters

    @Test
    func optionalQueryParameterIsCompactMapped() {
        assertMacroExpansion(
            """
            @API(host: "https://api.example.com")
            protocol API {
                @Get("/search")
                func search(query term: String, query page: Int?) async throws(APIError<ErrorDto>) -> [UserDto]
            }
            """,
            expandedSource: """
            protocol API {
                func search(query term: String, query page: Int?) async throws(APIError<ErrorDto>) -> [UserDto]
            }

            // @unchecked Sendable: mock closures are nil in production and thread-safe by design.
            // Assigning mock closures concurrently with active calls is a caller error.
            struct APIClient: API, @unchecked Sendable {
                static let _apiConfiguration = Beam::APIConfiguration(
                    host: "https://api.example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: Beam::APIConfiguration

                init(session: (any Beam::SessionProtocol)? = nil) {
                    _config = Self._apiConfiguration.replacing(session: session)
                }
                var onSearch: ((String, Int?) async throws(APIError<ErrorDto>) -> [UserDto])?

                func search(query term: String, query page: Int?) async throws(APIError<ErrorDto>) -> [UserDto] {
                    let endpoint = Beam::Endpoint<[UserDto], APIError<ErrorDto>._Failure>(
                            _config,
                            request: _config._request(.get, "/search", query: [Beam::_Route.query("term", term), Beam::_Route.query("page", page)].flatMap {
                                    $0
                                })
                        ).mocking(onSearch.map { mock in
                            .init(_unchecked: { (_) async throws(APIError<ErrorDto>) in
                                    return try await mock(term, page)
                                })
                        })
                    return try await endpoint.data()
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Static + dynamic header merge

    @Test
    func staticAndDynamicHeadersAreMerged() {
        assertMacroExpansion(
            """
            @API(host: "https://api.example.com")
            protocol API {
                @Get("/me", headers: ["X-Static": "1"])
                func me(header token: String) async throws(APIError<ErrorDto>) -> UserDto
            }
            """,
            expandedSource: """
            protocol API {
                func me(header token: String) async throws(APIError<ErrorDto>) -> UserDto
            }

            // @unchecked Sendable: mock closures are nil in production and thread-safe by design.
            // Assigning mock closures concurrently with active calls is a caller error.
            struct APIClient: API, @unchecked Sendable {
                static let _apiConfiguration = Beam::APIConfiguration(
                    host: "https://api.example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: Beam::APIConfiguration

                init(session: (any Beam::SessionProtocol)? = nil) {
                    _config = Self._apiConfiguration.replacing(session: session)
                }
                var onMe: ((String) async throws(APIError<ErrorDto>) -> UserDto)?

                func me(header token: String) async throws(APIError<ErrorDto>) -> UserDto {
                    let endpoint = Beam::Endpoint<UserDto, APIError<ErrorDto>._Failure>(
                            _config,
                            request: _config._request(.get, "/me", headers: Beam::_Route.headers(_config.headers, ["X-Static": "1"], Beam::_Route.header("token", token)))
                        ).mocking(onMe.map { mock in
                            .init(_unchecked: { (_) async throws(APIError<ErrorDto>) in
                                    return try await mock(token)
                                })
                        })
                    return try await endpoint.data()
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Per-route config override

    @Test
    func timeoutRetryAndAuthProduceReplacingCall() {
        assertMacroExpansion(
            """
            @API(host: "https://api.example.com")
            protocol API {
                @Get("/critical", timeout: .seconds(120), retry: .resilient, auth: .optional, json: .iso8601)
                func critical() async throws(APIError<ErrorDto>) -> UserDto
            }
            """,
            expandedSource: """
            protocol API {
                func critical() async throws(APIError<ErrorDto>) -> UserDto
            }

            // @unchecked Sendable: mock closures are nil in production and thread-safe by design.
            // Assigning mock closures concurrently with active calls is a caller error.
            struct APIClient: API, @unchecked Sendable {
                static let _apiConfiguration = Beam::APIConfiguration(
                    host: "https://api.example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: Beam::APIConfiguration

                init(session: (any Beam::SessionProtocol)? = nil) {
                    _config = Self._apiConfiguration.replacing(session: session)
                }
                var onCritical: (() async throws(APIError<ErrorDto>) -> UserDto)?

                func critical() async throws(APIError<ErrorDto>) -> UserDto {
                    let endpoint = Beam::Endpoint<UserDto, APIError<ErrorDto>._Failure>(
                            _config,
                            config: _config.config.replacing(retry: Beam::RetryPolicy.resilient, timeout: Swift::Duration.seconds(120), authPolicy: Beam::AuthPolicy.optional, json: Beam::JSONCoding.iso8601),
                            request: _config._request(.get, "/critical")
                        ).mocking(onCritical.map { mock in
                            .init(_unchecked: { (_) async throws(APIError<ErrorDto>) in
                                    return try await mock()
                                })
                        })
                    return try await endpoint.data()
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Absolute URL override

    @Test
    func absoluteURLParameterBypassesHostAndBase() {
        assertMacroExpansion(
            """
            @API(host: "https://api.example.com", base: "/v1")
            protocol API {
                @Get
                func proxy(url: URL) async throws(APIError<ErrorDto>) -> UserDto
            }
            """,
            expandedSource: """
            protocol API {
                func proxy(url: URL) async throws(APIError<ErrorDto>) -> UserDto
            }

            // @unchecked Sendable: mock closures are nil in production and thread-safe by design.
            // Assigning mock closures concurrently with active calls is a caller error.
            struct APIClient: API, @unchecked Sendable {
                static let _apiConfiguration = Beam::APIConfiguration(
                    host: "https://api.example.com",
                    base: "/v1",
                    headers: [:]
                )

                private let _config: Beam::APIConfiguration

                init(session: (any Beam::SessionProtocol)? = nil) {
                    _config = Self._apiConfiguration.replacing(session: session)
                }
                var onProxy: ((URL) async throws(APIError<ErrorDto>) -> UserDto)?

                func proxy(url: URL) async throws(APIError<ErrorDto>) -> UserDto {
                    let endpoint = Beam::Endpoint<UserDto, APIError<ErrorDto>._Failure>(
                            _config,
                            request: _config.request(.get, url: Beam::_Route.absoluteURL(url), route: "API.proxy")
                        ).mocking(onProxy.map { mock in
                            .init(_unchecked: { (_) async throws(APIError<ErrorDto>) in
                                    return try await mock(url)
                                })
                        })
                    return try await endpoint.data()
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Diagnostics

    @Test
    func invalidPathCharactersEmitWarning() {
        assertMacroExpansion(
            """
            @API(host: "https://api.example.com")
            protocol API {
                @Get("/bad path")
                func fetch() async throws(APIError<ErrorDto>) -> UserDto
            }
            """,
            expandedSource: """
            protocol API {
                func fetch() async throws(APIError<ErrorDto>) -> UserDto
            }

            // @unchecked Sendable: mock closures are nil in production and thread-safe by design.
            // Assigning mock closures concurrently with active calls is a caller error.
            struct APIClient: API, @unchecked Sendable {
                static let _apiConfiguration = Beam::APIConfiguration(
                    host: "https://api.example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: Beam::APIConfiguration

                init(session: (any Beam::SessionProtocol)? = nil) {
                    _config = Self._apiConfiguration.replacing(session: session)
                }
                var onFetch: (() async throws(APIError<ErrorDto>) -> UserDto)?

                func fetch() async throws(APIError<ErrorDto>) -> UserDto {
                    let endpoint = Beam::Endpoint<UserDto, APIError<ErrorDto>._Failure>(
                            _config,
                            request: _config._request(.get, "/bad path")
                        ).mocking(onFetch.map { mock in
                            .init(_unchecked: { (_) async throws(APIError<ErrorDto>) in
                                    return try await mock()
                                })
                        })
                    return try await endpoint.data()
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Route path '/bad path' contains invalid URL characters (spaces, <, >, |, \\, ^, `)",
                    line: 3,
                    column: 10,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Error: @API must be applied to a protocol

    @Test
    func applyingToNonProtocolThrows() {
        assertMacroExpansion(
            """
            @API(host: "https://api.example.com")
            struct NotAProtocol {}
            """,
            expandedSource: """
            struct NotAProtocol {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@API can only be applied to protocols",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }
}

// MARK: - Label-based roles and syntactic checks
//
// The macro decides each parameter's role from its label and emits a call to a
// `Beam::_Route` overload; the type-dependent behaviour of those overloads is
// covered end to end in BeamTests (MacroSyntaxShapeTests).

// Serialized as a precaution: one early parallel run gave inconsistent expansions
// that 50 later parallel runs did not reproduce. It costs nothing at this size.
@Suite(.serialized)
struct MacroSyntaxRecognitionTests {

    /// Expands `source` and returns only the generated client (the original protocol,
    /// which also contains the method signatures, is dropped), with whitespace
    /// collapsed so assertions do not depend on the macro's indentation.
    private func expansion(of source: String) -> String {
        let file = Parser.parse(source: source)
        let context = BasicMacroExpansionContext()
        let expanded = file.expand(macros: testMacros, contextGenerator: { _ in context }).description
        let client = expanded.range(of: "struct APIClient").map { String(expanded[$0.lowerBound...]) } ?? ""
        return client.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The diagnostic messages emitted while expanding `source`.
    private func diagnosticMessages(of source: String) -> [String] {
        let file = Parser.parse(source: source)
        let context = BasicMacroExpansionContext()
        _ = file.expand(macros: testMacros, contextGenerator: { _ in context })
        return context.diagnostics.map(\.message)
    }

    private func route(_ members: String) -> String {
        expansion(of: """
            @API(host: "https://api.example.com")
            protocol API {
            \(members)
            }
            """)
    }

    // MARK: Nothing written is dropped silently

    @Test
    func aDownloadSendsItsBody() {
        let code = route("""
                @Post("/report", task: .download)
                func report(body: Filter) async throws(APIError<E>) -> URL
            """)
        #expect(code.contains("body: Beam::_Route.body(body)"))
    }

    @Test
    func aSocketCantHaveAnAbsoluteURL() {
        let source = """
            @API(host: "https://api.example.com")
            protocol API {
                @Socket("/live")
                func live(url: URL) async throws(APIError<E>) -> WebSocketConnection<Msg, Msg, E>
            }
            """
        #expect(diagnosticMessages(of: source).contains { $0.hasPrefix("A WebSocket route connects to its API's host and path") })
        // A `{url}` placeholder is a path value, not an absolute target.
        let placeholder = source.replacingOccurrences(of: "\"/live\"", with: "\"/live/{url}\"").replacingOccurrences(of: "url: URL", with: "url: String")
        #expect(diagnosticMessages(of: placeholder).isEmpty)
    }

    @Test
    func aSocketCantHaveABody() {
        let source = """
            @API(host: "https://api.example.com")
            protocol API {
                @Socket("/live")
                func live(body: Hello) async throws(APIError<E>) -> WebSocketConnection<Msg, Msg, E>
            }
            """
        #expect(diagnosticMessages(of: source).contains { $0.hasPrefix("A WebSocket route can't have a body") })
    }

    /// GET, HEAD and TRACE carry no request content (RFC 9110 §9.3); URLSession
    /// fails, hangs or drops it (verified on the wire, macOS and iOS 27 simulator).
    @Test(arguments: ["Get", "Head", "Trace"])
    func aContentlessMethodCantSendABodyOrUpload(_ method: String) {
        func messages(_ route: String, _ parameter: String = "body: Filter") -> [String] {
            diagnosticMessages(of: """
                @API(host: "https://api.example.com")
                protocol API {
                    \(route)
                    func send(\(parameter)) async throws(APIError<E>) -> Dto
                }
                """)
        }
        let error = "A \(method.uppercased()) route can't send a body or upload"
        for task in ["", ", task: .bytes", ", task: .download", ", task: .upload"] {
            #expect(messages("@\(method)(\"/a\"\(task))").contains { $0.hasPrefix(error) }, "\(method)\(task)")
        }
        // An upload of a file is content too.
        #expect(messages("@\(method)(\"/a\", task: .upload)", "url file: URL").contains { $0.hasPrefix(error) })
        // Without a body it compiles.
        #expect(messages("@\(method)(\"/a\")", "query id: Int").isEmpty)
    }

    /// The RFC allows content in POST, PUT, PATCH, OPTIONS and DELETE (only when the server
    /// supports it), and URLSession sends it: the app deletes with a body.
    @Test(arguments: ["Post", "Put", "Patch", "Delete", "Options"])
    func methodsWithContentSendTheBody(_ method: String) {
        let source = """
            @API(host: "https://api.example.com")
            protocol API {
                @\(method)("/a")
                func send(body: Filter) async throws(APIError<E>) -> Dto
            }
            """
        #expect(diagnosticMessages(of: source).isEmpty)
    }

    @Test
    func resumeDataIsReadByItsLabelWhateverItsName() {
        let code = route("""
                @Get("/file", task: .download)
                func file(resumeFrom previous: Data) async throws(APIError<E>) -> URL
            """)
        #expect(code.contains("return try await endpoint.download(resumeFrom: Beam::_Route.resumeData(previous), onProgress: onProgress)"))
        #expect(!code.contains("_Route.queryItems(previous)"))
        // Handles take it in `start(resumeFrom:)`, not when they are created.
        #expect(code.contains("func fileTask() -> Beam::DownloadTask"))
    }

    @Test
    func anUploadResumesFromItsResumeData() {
        let code = route("""
                @Post("/file", task: .upload)
                func send(id: Int, body: Dto, resumeFrom previous: Data) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("let _uploadContent = Beam::_Route.uploadBody(body) return try await endpoint.upload(_uploadContent, resumeFrom: Beam::_Route.resumeData(previous), onProgress: onProgress)"))
        // The handle takes the content when created, and the resume data in `start(resumeFrom:)`.
        #expect(code.contains("func sendTask(id: Int, body: Dto) -> Beam::UploadTask"))
        #expect(code.contains("let _uploadContent = Beam::_Route.uploadBody(body) return endpoint.uploadTask(_uploadContent) }"))
        // The mock goes with the endpoint: it answers the direct call and the handles.
        #expect(code.contains(".mocking(onSend.map { mock in .init(_unchecked: { (_resume) async throws(APIError<E>) in let previous = _resume ?? Foundation::Data(); return try await mock(id, body, previous) }) })"))
        #expect(!code.contains("if let mock"))
    }

    /// Resuming fails over to the file: the route resumes, and its retries upload the file.
    @Test
    func anUploadCanResumeAndUploadAFile() {
        let source = """
            @API(host: "https://api.example.com")
            protocol API {
                @Post("/file", task: .upload)
                func send(url file: URL, resumeFrom previous: Data) async throws(APIError<E>) -> Dto
            }
            """
        #expect(diagnosticMessages(of: source).isEmpty)
        #expect(expansion(of: source).contains("let _uploadContent = Beam::UploadContent.file(Beam::_Route.uploadFile(file)) return try await endpoint.upload(_uploadContent, resumeFrom: Beam::_Route.resumeData(previous), onProgress: onProgress)"))
    }

    /// A path is relative to the API's base; an empty one is the base itself.
    @Test
    func aPathStartsWithASlash() {
        let source = """
            @API(host: "https://api.example.com")
            protocol API {
                @Get("users")
                func users() async throws(APIError<E>) -> Dto
                @Get("")
                func base() async throws(APIError<E>) -> Dto
            }
            """
        #expect(diagnosticMessages(of: source) == ["Route path 'users' must start with '/'"])
    }

    @Test
    func anUploadNeedsContent() {
        let source = """
            @API(host: "https://api.example.com")
            protocol API {
                @Post("/file", task: .upload)
                func send(id: Int, resumeFrom previous: Data) async throws(APIError<E>) -> Dto
            }
            """
        #expect(diagnosticMessages(of: source).contains { $0.hasPrefix("An upload route needs something to upload") })
    }

    /// The body is uploaded, not put in the request.
    @Test
    func anUploadsBodyIsNotInTheRequest() {
        let code = route("""
                @Post("/file", task: .upload)
                func send(body: Dto) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("request: _config._request(.post, \"/file\")"))
        #expect(!code.contains("body: Beam::_Route.body(body)"))
    }

    /// Its file would be uploaded and its body dropped.
    @Test
    func anUploadCantHaveABodyAndAFile() {
        let source = """
            @API(host: "https://api.example.com")
            protocol API {
                @Post("/file", task: .upload)
                func send(body: Dto, url file: URL) async throws(APIError<E>) -> Dto
                @Post("/file", task: .upload)
                func body(body: Dto) async throws(APIError<E>) -> Dto
                @Post("/file", task: .upload)
                func file(url file: URL) async throws(APIError<E>) -> Dto
            }
            """
        let messages = diagnosticMessages(of: source).filter { $0.hasPrefix("An upload route uploads its body or its file, not both") }
        #expect(messages.count == 1)
    }

    @Test
    func aTaskThatIsntWrittenAsAMemberIsAnError() {
        let source = """
            @API(host: "https://api.example.com")
            protocol API {
                @Get("/file", task: kind)
                func file() async throws(APIError<E>) -> URL
            }
            """
        #expect(diagnosticMessages(of: source).contains { $0.hasPrefix("Route 'task:' must be written as") })
        #expect(diagnosticMessages(of: source.replacingOccurrences(of: "kind", with: "Beam._TaskKind.download")).isEmpty)
    }

    // MARK: Route attributes

    @Test
    func routeAttributeIsRecognisedWithModuleQualifier() {
        let code = route("""
                @Beam.Get("/a")
                func a() async throws(APIError<E>) -> Dto
                @Beam::Post("/b")
                func b() async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("request: _config._request(.get, \"/a\")"))
        #expect(code.contains("request: _config._request(.post, \"/b\")"))
    }

    @Test
    func attributeFromAnotherModuleIsNotARoute() {
        let code = route("""
                @Other.Get("/a")
                func a() async throws(APIError<E>) -> Dto
            """)
        #expect(!code.contains("func a() async"))
    }

    @Test
    func taskKindSpellings() {
        for kind in [".download", "_TaskKind.download", "Beam._TaskKind.download"] {
            let code = route("""
                    @Get("/file", task: \(kind))
                    func file() async throws(APIError<E>) -> URL
                """)
            #expect(code.contains("Beam::DownloadTask<APIError<E>._Failure>"), "task: \(kind) must select download")
        }
    }

    // MARK: Thrown type

    @Test
    func thrownTypeIsUsedAsWritten() {
        for thrown in ["APIError<ErrorDto>", "Beam.APIError<ErrorDto>", "MyAPIError"] {
            let code = route("""
                    @Get("/a")
                    func a() async throws(\(thrown)) -> Dto
                """)
            #expect(code.contains("func a() async throws(\(thrown)) -> Dto {"), "\(thrown)")
            #expect(code.contains("Beam::Endpoint<Dto, \(thrown)._Failure>("), "\(thrown)")
            #expect(code.contains("var onA: (() async throws(\(thrown)) -> Dto)?"), "\(thrown)")
        }
    }

    // MARK: Parameter roles

    @Test
    func queryLabelDelegatesToTheQueryOverloads() {
        let code = route("""
                @Get("/a")
                func a(query page: Optional<Int>, query term: String) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("query: [Beam::_Route.query(\"page\", page), Beam::_Route.query(\"term\", term)].flatMap { $0 }"))
    }

    @Test
    func unlabeledParametersMayBeQueryItems() {
        let code = route("""
                @Get("/a")
                func a(params: Params) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("query: Beam::_Route.queryItems(params))"))
    }

    @Test
    func headerLabelsAreLayeredOverAPIAndRouteHeaders() {
        let code = route("""
                @Get("/a", headers: ["X-Static": "1"])
                func a(header token: String?) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("headers: Beam::_Route.headers(_config.headers, [\"X-Static\": \"1\"], Beam::_Route.header(\"token\", token)))"))
    }

    @Test
    func bodyLabelDelegatesToTheBodyOverloads() {
        let code = route("""
                @Post("/a")
                func a(body request: Dto?) async throws(APIError<E>)
            """)
        #expect(code.contains("body: Beam::_Route.body(request))"))
    }

    @Test
    func pathPlaceholdersUseTheInternalName() {
        let code = route("""
                @Get("/users/{id}")
                func a(id identifier: Int) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("\"/users/{id}\", values: [\"id\": Beam::_Route.path(identifier)])"))
    }

    // MARK: Placeholders

    @Test
    func placeholderWithoutParameterReadsAPIValues() {
        let code = route("""
                @Get("/v2/{userID}/documents/{documentId}")
                func a(documentId: String) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains(
            "values: [\"userID\": Beam::_Route.shared(\"userID\", Beam::APIValues.userID), \"documentId\": Beam::_Route.path(documentId)])"
        ))
    }

    @Test
    func routeQueryKeepsOrderLiteralsAndPlaceholders() {
        let code = route("""
                @Get("/a", query: ["$filter": "{\\"push.status\\":1}", "lang": "{locale}", "page": "{page}"])
                func a(page: Int?) async throws(APIError<E>) -> Dto
            """)
        // A value is a placeholder only when it is exactly `{identifier}`.
        #expect(code.contains(
            #"routeQuery: ["$filter": .value("{\"push.status\":1}"), "lang": Beam::_Route.shared("locale", Beam::APIValues.locale), "page": Beam::_Route.queryValue(page)])"#
        ))
        // The parameter feeds the placeholder only: it is not also sent as query items.
        #expect(!code.contains(", query:"))
    }

    @Test
    func interpolatedPathIsAnError() {
        let diagnostics = diagnosticMessages(of: """
            @API(host: "https://api.example.com")
            protocol API {
                @Get("/v2/\\(Defs.userID)/settings")
                func a() async throws(APIError<E>) -> Dto
            }
            """)
        #expect(diagnostics.contains { $0.contains("can't use string interpolation") })
    }

    @Test
    func invalidPlaceholderAndNonLiteralQueryAreErrors() {
        let diagnostics = diagnosticMessages(of: """
            @API(host: "https://api.example.com")
            protocol API {
                @Get("/a/{user-id}", query: Constants.query)
                func a() async throws(APIError<E>) -> Dto
            }
            """)
        #expect(diagnostics.contains { $0.contains("'{user-id}' is not a valid placeholder") })
        #expect(diagnostics.contains { $0.contains("'query:' must be a dictionary literal") })
    }

    @Test
    func urlLabelIsTheAbsoluteTargetUsingTheInternalName() {
        let code = route("""
                @Get
                func a(url target: URL) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("request: _config.request(.get, url: Beam::_Route.absoluteURL(target), route: \"API.a\")"))
    }

    @Test
    func urlLabelInAnUploadRouteIsTheFile() {
        let code = route("""
                @Put("/a", task: .upload)
                func a(url file: URL) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("let _uploadContent = Beam::UploadContent.file(Beam::_Route.uploadFile(file)) return try await endpoint.upload(_uploadContent, onProgress: onProgress)"))
        #expect(code.contains("func aTask(url file: URL) -> Beam::UploadTask<Dto, APIError<E>._Failure>"))
        // The handle takes the file when it is created, and so does the endpoint's mock.
        #expect(code.contains(".mocking(onA.map { mock in .init(_unchecked: { (_) async throws(APIError<E>) in return try await mock(file) }) })"))
    }

    /// The client keeps a parameter without a label: otherwise it wouldn't conform.
    @Test
    func unlabeledParametersKeepNoLabel() {
        let code = route("""
                @Get("/a", task: .download)
                func a(_ items: [URLQueryItem]) async throws(APIError<E>) -> URL
            """)
        #expect(code.contains("func a(_ items: [URLQueryItem]) async throws(APIError<E>) -> URL { try await a(items, onProgress: nil) }"))
        #expect(code.contains("private func _aEndpoint(_ items: [URLQueryItem])"))
        #expect(code.contains("let endpoint = _aEndpoint(items)"))
        #expect(code.contains("func aTask(_ items: [URLQueryItem]) -> Beam::DownloadTask"))
    }

    // MARK: Generic results

    @Test
    func byteStreamAndWebSocketResultsAreInferredFromTheDeclaredReturnType() {
        let code = route("""
                @Get("/feed", task: .bytes)
                func feed() async throws(APIError<E>) -> Beam.ByteStream<Chunk>
                @Socket("/chat")
                func chat() async throws(APIError<E>) -> ChatConnection
            """)
        #expect(code.contains("func feed() async throws(APIError<E>) -> Beam.ByteStream<Chunk> { return try await Beam::Endpoint<_, APIError<E>._Failure>("))
        #expect(code.contains(").stream() }"))
        #expect(code.contains("func chat() async throws(APIError<E>) -> ChatConnection { if let mock = onChat { return try await mock() } return try await Beam::Endpoint<_, APIError<E>._Failure>("))
        #expect(code.contains("var onChat: (() async throws(APIError<E>) -> ChatConnection)?"))
        #expect(!code.contains("var onFeed"))
        #expect(code.contains(").connect() }"))
    }

    // MARK: Mocks

    @Test
    func implicitlyUnwrappedParametersAreOptionalInTheMockType() {
        let code = route("""
                @Get("/a")
                func a(query page: Int!) async throws(APIError<E>) -> Dto
            """)
        #expect(code.contains("func a(query page: Int!) async"))
        #expect(code.contains("var onA: ((Int?) async throws(APIError<E>) -> Dto)?"))
    }

    // MARK: API configuration

    @Test
    func apiConfigurationArgumentsAreForwarded() {
        let code = expansion(of: """
            @API(host: "https://api.example.com", config: RequestConfig(retry: .none), interceptors: [Stamp()], logLevel: .error)
            protocol API {
                @Get("/a")
                func a() async throws(APIError<E>) -> Dto
            }
            """)
        #expect(code.contains("headers: [:], config: RequestConfig(retry: .none), interceptors: [Stamp()], logLevel: .error )"))
    }

    // MARK: - Background session

    private static let transferRoutes = """
        protocol API {
            @Post("/documents", task: .upload)
            func upload(body: HTTPBody) async throws(APIError<E>)
            @Get("/documents/{id}", task: .download)
            func download(id: String) async throws(APIError<E>) -> URL
            @Get("/me")
            func me() async throws(APIError<E>) -> Dto
        }
        """

    @Test
    func aBackgroundSessionAddsBackgroundHandlesToTransferRoutes() {
        let code = expansion(of: """
            @API(host: "https://api.example.com", session: Sessions.pinned, background: Sessions.transfers)
            \(Self.transferRoutes)
            """)
        #expect(code.contains("session: Sessions.pinned, background: Sessions.transfers )"))
        #expect(code.contains("func uploadBackgroundTask(body: HTTPBody) -> Beam::BackgroundUploadTask<Void, APIError<E>._Failure>"))
        #expect(code.contains("let _uploadContent = Beam::_Route.uploadBody(body) return endpoint.backgroundUploadTask(on: Beam::_Route.background(_config), _uploadContent) }"))
        #expect(code.contains("func downloadBackgroundTask(id: String) -> Beam::BackgroundDownloadTask<APIError<E>._Failure>"))
        // Data routes have no background variant.
        #expect(!code.contains("meBackgroundTask"))
    }

    /// A transfer route builds its endpoint once, in a private helper shared by the
    /// direct call and every handle.
    @Test
    func transferRoutesShareOneEndpointHelper() {
        let code = expansion(of: """
            @API(host: "https://api.example.com", session: Sessions.pinned, background: Sessions.transfers)
            \(Self.transferRoutes)
            """)
        // The body is the upload's content, not part of the endpoint.
        #expect(code.contains("private func _uploadEndpoint() -> Beam::Endpoint<Void, APIError<E>._Failure>"))
        #expect(code.components(separatedBy: "let endpoint = _uploadEndpoint()").count - 1 == 3)
        #expect(code.contains("private func _downloadEndpoint(id: String) -> Beam::Endpoint<URL, APIError<E>._Failure>"))
        #expect(code.components(separatedBy: "let endpoint = _downloadEndpoint(id: id)").count - 1 == 3)
        // Built in three places only: the two helpers and `me` (plus the helpers' return types).
        #expect(code.components(separatedBy: "Beam::Endpoint<").count - 1 == 5)
    }

    /// Without `background:`, the background handles don't exist, so calling them
    /// doesn't compile.
    @Test
    func withoutABackgroundSessionThereAreNoBackgroundHandles() {
        let code = expansion(of: """
            @API(host: "https://api.example.com")
            \(Self.transferRoutes)
            """)
        #expect(!code.contains("BackgroundTask"))
        #expect(!code.contains("background:"))
    }

    // MARK: WebSockets

    @Test
    func socketOptionsOverrideTheAPIsSocketConfig() {
        let code = route("""
                @Socket("/chat", retry: .none, ping: .seconds(20), reconnect: .resilient, protocols: ["chat.v2"])
                func chat() async throws(APIError<E>) -> WebSocketConnection<Event, Command, E>
            """)
        #expect(code.contains("connect(socket: _config.socket.replacing(ping: Swift::Duration.seconds(20), reconnect: Beam::RetryPolicy.resilient, protocols: [\"chat.v2\"]))"))
        #expect(code.contains("config: _config.config.replacing(retry: Beam::RetryPolicy.none)"))
        // Without socket options, the API's config as it is.
        #expect(route("""
                @Socket("/chat")
                func chat() async throws(APIError<E>) -> WebSocketConnection<Event, Command, E>
            """).contains("connect()"))
    }

    @Test
    func socketLiteralsOutOfRangeDontCompile() {
        func messages(_ options: String) -> [String] {
            diagnosticMessages(of: """
                @API(host: "wss://api.example.com")
                protocol API {
                    @Socket("/chat", \(options))
                    func chat() async throws(APIError<E>) -> WebSocketConnection<Event, Command, E>
                }
                """)
        }
        #expect(messages("ping: .seconds(0)").contains { $0.contains("out of range") })
        #expect(messages("ping: .milliseconds(400_000)").contains { $0.contains("out of range") })
        #expect(messages("maxMessageSize: 0").contains { $0.contains("greater than zero") })
        #expect(messages("ping: .seconds(20), maxMessageSize: 4_000_000").isEmpty)
    }

    @Test
    func servicesNoRouteUsesAreWarnedAbout() {
        let messages = diagnosticMessages(of: """
            @API(host: "https://api.example.com", background: URLSessions.background, socket: .chat)
            protocol API {
                @Get("/a")
                func a() async throws(APIError<E>) -> Dto
            }
            """)
        #expect(messages.contains { $0.hasPrefix("'socket:' has no effect") })
        #expect(messages.contains { $0.hasPrefix("'background:' has no effect") })
    }
}

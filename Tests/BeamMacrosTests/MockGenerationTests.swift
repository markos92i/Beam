//
//  MockGenerationTests.swift
//  Beam
//
//  Tests for @API(mock: true) mock struct generation.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
import BeamMacros

private let testMacros: [String: Macro.Type] = [
    "API": APIMacro.self,
    "Get": GetMacro.self,
    "Post": PostMacro.self,
    "Put": PutMacro.self,
    "Delete": DeleteMacro.self,
    "Socket": SocketMacro.self,
]

// MARK: - Mock Generation Tests

@Suite("Mock Generation")
struct MockGenerationTests {

    @Test("No mock generated when mock param is omitted")
    func noMockWithoutFlag() {
        assertMacroExpansion(
            """
            @API(host: "https://example.com")
            protocol UsersAPI {
                @Get("/users/{id}")
                func fetch(id: Int) async throws(APIError<Void>) -> UserDto
            }
            """,
            expandedSource: """
            protocol UsersAPI {
                func fetch(id: Int) async throws(APIError<Void>) -> UserDto
            }

            struct UsersAPIClient: UsersAPI, Sendable {
                static let _apiConfiguration = _APIConfiguration(
                    host: "https://example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: _APIConfiguration

                init(session: (any SessionProtocol)? = nil) {
                    if let session {
                        _config = _APIConfiguration(
                            host: Self._apiConfiguration.host,
                            base: Self._apiConfiguration.base,
                            headers: Self._apiConfiguration.headers,
                            session: session,
                            auth: Self._apiConfiguration.auth,
                            crash: Self._apiConfiguration.crash,
                            mapper: Self._apiConfiguration.mapper,
                            interceptors: Self._apiConfiguration.interceptors
                        )
                    } else {
                        _config = Self._apiConfiguration
                    }
                }
                func fetch(id: Int) async throws(APIError<Void>) -> UserDto {
                    let endpoint = Endpoint<UserDto, Void>(
                        session: _config.session,
                        auth: _config.auth,
                        crash: _config.crash,
                        mapper: _config.mapper,
                        config: .standard,
                        authPolicy: .required,
                        interceptors: _config.interceptors,
                        logLevel: _config.logLevel,
                        api: APIRequest(
                            method: .get,
                            host: _config.host,
                            path: _config.base + "/users/\\(id)",
                            query: [],
                            headers: _config.headers,
                            body: nil
                        )
                    )
                    return try await endpoint.data()
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test("Mock generated with mock: true — single method with param")
    func mockWithSingleParam() {
        assertMacroExpansion(
            """
            @API(host: "https://example.com", mock: true)
            protocol UsersAPI {
                @Get("/users/{id}")
                func fetch(id: Int) async throws(APIError<Void>) -> UserDto
            }
            """,
            expandedSource: """
            protocol UsersAPI {
                func fetch(id: Int) async throws(APIError<Void>) -> UserDto
            }

            struct UsersAPIClient: UsersAPI, Sendable {
                static let _apiConfiguration = _APIConfiguration(
                    host: "https://example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: _APIConfiguration

                init(session: (any SessionProtocol)? = nil) {
                    if let session {
                        _config = _APIConfiguration(
                            host: Self._apiConfiguration.host,
                            base: Self._apiConfiguration.base,
                            headers: Self._apiConfiguration.headers,
                            session: session,
                            auth: Self._apiConfiguration.auth,
                            crash: Self._apiConfiguration.crash,
                            mapper: Self._apiConfiguration.mapper,
                            interceptors: Self._apiConfiguration.interceptors
                        )
                    } else {
                        _config = Self._apiConfiguration
                    }
                }
                func fetch(id: Int) async throws(APIError<Void>) -> UserDto {
                    let endpoint = Endpoint<UserDto, Void>(
                        session: _config.session,
                        auth: _config.auth,
                        crash: _config.crash,
                        mapper: _config.mapper,
                        config: .standard,
                        authPolicy: .required,
                        interceptors: _config.interceptors,
                        logLevel: _config.logLevel,
                        api: APIRequest(
                            method: .get,
                            host: _config.host,
                            path: _config.base + "/users/\\(id)",
                            query: [],
                            headers: _config.headers,
                            body: nil
                        )
                    )
                    return try await endpoint.data()
                }
            }

            struct UsersAPIMock: UsersAPI {
                var fetchMock: (Int) async throws(APIError<Void>) -> UserDto = { _ in
                    fatalError("UsersAPIMock.fetch not stubbed")
                }

                func fetch(id: Int) async throws(APIError<Void>) -> UserDto {
                    try await fetchMock(id)
                }

            }
            """,
            macros: testMacros
        )
    }

    @Test("Mock with Void return method")
    func mockVoidReturn() {
        assertMacroExpansion(
            """
            @API(host: "https://example.com", mock: true)
            protocol ItemsAPI {
                @Delete("/items/{id}")
                func remove(id: Int) async throws(APIError<ErrorDto>)
            }
            """,
            expandedSource: """
            protocol ItemsAPI {
                func remove(id: Int) async throws(APIError<ErrorDto>)
            }

            struct ItemsAPIClient: ItemsAPI, Sendable {
                static let _apiConfiguration = _APIConfiguration(
                    host: "https://example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: _APIConfiguration

                init(session: (any SessionProtocol)? = nil) {
                    if let session {
                        _config = _APIConfiguration(
                            host: Self._apiConfiguration.host,
                            base: Self._apiConfiguration.base,
                            headers: Self._apiConfiguration.headers,
                            session: session,
                            auth: Self._apiConfiguration.auth,
                            crash: Self._apiConfiguration.crash,
                            mapper: Self._apiConfiguration.mapper,
                            interceptors: Self._apiConfiguration.interceptors
                        )
                    } else {
                        _config = Self._apiConfiguration
                    }
                }
                func remove(id: Int) async throws(APIError<ErrorDto>) {
                    let endpoint = Endpoint<Void, ErrorDto>(
                        session: _config.session,
                        auth: _config.auth,
                        crash: _config.crash,
                        mapper: _config.mapper,
                        config: .standard,
                        authPolicy: .required,
                        interceptors: _config.interceptors,
                        logLevel: _config.logLevel,
                        api: APIRequest(
                            method: .delete,
                            host: _config.host,
                            path: _config.base + "/items/\\(id)",
                            query: [],
                            headers: _config.headers,
                            body: nil
                        )
                    )
                    return try await endpoint.data()
                }
            }

            struct ItemsAPIMock: ItemsAPI {
                var removeMock: (Int) async throws(APIError<ErrorDto>) -> Void = { _ in
                    fatalError("ItemsAPIMock.remove not stubbed")
                }

                func remove(id: Int) async throws(APIError<ErrorDto>) {
                    try await removeMock(id)
                }

            }
            """,
            macros: testMacros
        )
    }

    @Test("Mock with no parameters")
    func mockNoParams() {
        assertMacroExpansion(
            """
            @API(host: "https://example.com", mock: true)
            protocol ConfigAPI {
                @Get("/config")
                func load() async throws(APIError<Void>) -> ConfigDto
            }
            """,
            expandedSource: """
            protocol ConfigAPI {
                func load() async throws(APIError<Void>) -> ConfigDto
            }

            struct ConfigAPIClient: ConfigAPI, Sendable {
                static let _apiConfiguration = _APIConfiguration(
                    host: "https://example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: _APIConfiguration

                init(session: (any SessionProtocol)? = nil) {
                    if let session {
                        _config = _APIConfiguration(
                            host: Self._apiConfiguration.host,
                            base: Self._apiConfiguration.base,
                            headers: Self._apiConfiguration.headers,
                            session: session,
                            auth: Self._apiConfiguration.auth,
                            crash: Self._apiConfiguration.crash,
                            mapper: Self._apiConfiguration.mapper,
                            interceptors: Self._apiConfiguration.interceptors
                        )
                    } else {
                        _config = Self._apiConfiguration
                    }
                }
                func load() async throws(APIError<Void>) -> ConfigDto {
                    let endpoint = Endpoint<ConfigDto, Void>(
                        session: _config.session,
                        auth: _config.auth,
                        crash: _config.crash,
                        mapper: _config.mapper,
                        config: .standard,
                        authPolicy: .required,
                        interceptors: _config.interceptors,
                        logLevel: _config.logLevel,
                        api: APIRequest(
                            method: .get,
                            host: _config.host,
                            path: _config.base + "/config",
                            query: [],
                            headers: _config.headers,
                            body: nil
                        )
                    )
                    return try await endpoint.data()
                }
            }

            struct ConfigAPIMock: ConfigAPI {
                var loadMock: () async throws(APIError<Void>) -> ConfigDto = {
                    fatalError("ConfigAPIMock.load not stubbed")
                }

                func load() async throws(APIError<Void>) -> ConfigDto {
                    try await loadMock()
                }

            }
            """,
            macros: testMacros
        )
    }

    @Test("Mock with multiple parameters")
    func mockMultipleParams() {
        assertMacroExpansion(
            """
            @API(host: "https://example.com", mock: true)
            protocol UsersAPI {
                @Put("/users/{id}")
                func update(id: Int, body request: UpdateRequest) async throws(APIError<Void>) -> UserDto
            }
            """,
            expandedSource: """
            protocol UsersAPI {
                func update(id: Int, body request: UpdateRequest) async throws(APIError<Void>) -> UserDto
            }

            struct UsersAPIClient: UsersAPI, Sendable {
                static let _apiConfiguration = _APIConfiguration(
                    host: "https://example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: _APIConfiguration

                init(session: (any SessionProtocol)? = nil) {
                    if let session {
                        _config = _APIConfiguration(
                            host: Self._apiConfiguration.host,
                            base: Self._apiConfiguration.base,
                            headers: Self._apiConfiguration.headers,
                            session: session,
                            auth: Self._apiConfiguration.auth,
                            crash: Self._apiConfiguration.crash,
                            mapper: Self._apiConfiguration.mapper,
                            interceptors: Self._apiConfiguration.interceptors
                        )
                    } else {
                        _config = Self._apiConfiguration
                    }
                }
                func update(id: Int, body request: UpdateRequest) async throws(APIError<Void>) -> UserDto {
                    let endpoint = Endpoint<UserDto, Void>(
                        session: _config.session,
                        auth: _config.auth,
                        crash: _config.crash,
                        mapper: _config.mapper,
                        config: .standard,
                        authPolicy: .required,
                        interceptors: _config.interceptors,
                        logLevel: _config.logLevel,
                        api: APIRequest(
                            method: .put,
                            host: _config.host,
                            path: _config.base + "/users/\\(id)",
                            query: [],
                            headers: _config.headers,
                            body: .json(request)
                        )
                    )
                    return try await endpoint.data()
                }
            }

            struct UsersAPIMock: UsersAPI {
                var updateMock: (Int, UpdateRequest) async throws(APIError<Void>) -> UserDto = { _, _ in
                    fatalError("UsersAPIMock.update not stubbed")
                }

                func update(id: Int, body request: UpdateRequest) async throws(APIError<Void>) -> UserDto {
                    try await updateMock(id, request)
                }

            }
            """,
            macros: testMacros
        )
    }

    @Test("Mock with multiple methods generates all handlers")
    func mockMultipleMethods() {
        assertMacroExpansion(
            """
            @API(host: "https://example.com", mock: true)
            protocol CrudAPI {
                @Get("/items/{id}")
                func fetch(id: Int) async throws(APIError<Void>) -> ItemDto

                @Post("/items")
                func create(body item: CreateRequest) async throws(APIError<Void>) -> ItemDto

                @Delete("/items/{id}")
                func remove(id: Int) async throws(APIError<Void>)
            }
            """,
            expandedSource: """
            protocol CrudAPI {
                func fetch(id: Int) async throws(APIError<Void>) -> ItemDto
                func create(body item: CreateRequest) async throws(APIError<Void>) -> ItemDto
                func remove(id: Int) async throws(APIError<Void>)
            }

            struct CrudAPIClient: CrudAPI, Sendable {
                static let _apiConfiguration = _APIConfiguration(
                    host: "https://example.com",
                    base: "",
                    headers: [:]
                )

                private let _config: _APIConfiguration

                init(session: (any SessionProtocol)? = nil) {
                    if let session {
                        _config = _APIConfiguration(
                            host: Self._apiConfiguration.host,
                            base: Self._apiConfiguration.base,
                            headers: Self._apiConfiguration.headers,
                            session: session,
                            auth: Self._apiConfiguration.auth,
                            crash: Self._apiConfiguration.crash,
                            mapper: Self._apiConfiguration.mapper,
                            interceptors: Self._apiConfiguration.interceptors
                        )
                    } else {
                        _config = Self._apiConfiguration
                    }
                }
                func fetch(id: Int) async throws(APIError<Void>) -> ItemDto {
                    let endpoint = Endpoint<ItemDto, Void>(
                        session: _config.session,
                        auth: _config.auth,
                        crash: _config.crash,
                        mapper: _config.mapper,
                        config: .standard,
                        authPolicy: .required,
                        interceptors: _config.interceptors,
                        logLevel: _config.logLevel,
                        api: APIRequest(
                            method: .get,
                            host: _config.host,
                            path: _config.base + "/items/\\(id)",
                            query: [],
                            headers: _config.headers,
                            body: nil
                        )
                    )
                    return try await endpoint.data()
                }
                func create(body item: CreateRequest) async throws(APIError<Void>) -> ItemDto {
                    let endpoint = Endpoint<ItemDto, Void>(
                        session: _config.session,
                        auth: _config.auth,
                        crash: _config.crash,
                        mapper: _config.mapper,
                        config: .standard,
                        authPolicy: .required,
                        interceptors: _config.interceptors,
                        logLevel: _config.logLevel,
                        api: APIRequest(
                            method: .post,
                            host: _config.host,
                            path: _config.base + "/items",
                            query: [],
                            headers: _config.headers,
                            body: .json(item)
                        )
                    )
                    return try await endpoint.data()
                }
                func remove(id: Int) async throws(APIError<Void>) {
                    let endpoint = Endpoint<Void, Void>(
                        session: _config.session,
                        auth: _config.auth,
                        crash: _config.crash,
                        mapper: _config.mapper,
                        config: .standard,
                        authPolicy: .required,
                        interceptors: _config.interceptors,
                        logLevel: _config.logLevel,
                        api: APIRequest(
                            method: .delete,
                            host: _config.host,
                            path: _config.base + "/items/\\(id)",
                            query: [],
                            headers: _config.headers,
                            body: nil
                        )
                    )
                    return try await endpoint.data()
                }
            }

            struct CrudAPIMock: CrudAPI {
                var fetchMock: (Int) async throws(APIError<Void>) -> ItemDto = { _ in
                    fatalError("CrudAPIMock.fetch not stubbed")
                }

                func fetch(id: Int) async throws(APIError<Void>) -> ItemDto {
                    try await fetchMock(id)
                }

                var createMock: (CreateRequest) async throws(APIError<Void>) -> ItemDto = { _ in
                    fatalError("CrudAPIMock.create not stubbed")
                }

                func create(body item: CreateRequest) async throws(APIError<Void>) -> ItemDto {
                    try await createMock(item)
                }

                var removeMock: (Int) async throws(APIError<Void>) -> Void = { _ in
                    fatalError("CrudAPIMock.remove not stubbed")
                }

                func remove(id: Int) async throws(APIError<Void>) {
                    try await removeMock(id)
                }

            }
            """,
            macros: testMacros
        )
    }
}

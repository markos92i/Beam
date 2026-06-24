//
//  InterceptorTests.swift
//  Beam
//

import Foundation
import Testing
@testable import Beam

// MARK: - Test Interceptors

struct HeaderInterceptor: RequestInterceptor {
    let key: String
    let value: String

    func intercept(request: URLRequest) async -> URLRequest {
        var request = request
        request.setValue(value, forHTTPHeaderField: key)
        return request
    }
}

struct ResponseBodyInterceptor: RequestInterceptor {
    let transform: @Sendable (Data) -> Data

    func intercept(response: Response) async -> Response {
        guard case .data(let data) = response.body else { return response }
        return Response(http: response.http, body: .data(transform(data)))
    }
}

struct StatusLoggingInterceptor: RequestInterceptor {
    let log: AtomicLog

    func intercept(response: Response) async -> Response {
        await log.append(response.http.statusCode)
        return response
    }
}

actor AtomicLog {
    var values: [Int] = []
    func append(_ value: Int) { values.append(value) }
}

// MARK: - Tests

@Suite
struct InterceptorTests {

    // MARK: - Request Interception

    @Test
    func singleInterceptorAddsHeader() async throws {
        let session = MockSession({ request in
            #expect(request.value(forHTTPHeaderField: "X-Custom") == "test-value")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let endpoint = Endpoint<String, Void>(
            session: session,
            interceptors: [HeaderInterceptor(key: "X-Custom", value: "test-value")],
            api: APIRequest(method: .get, host: "https://example.com", path: "/test")
        )

        _ = try await endpoint.data()
    }

    @Test
    func multipleInterceptorsApplyInOrder() async throws {
        let session = MockSession({ request in
            #expect(request.value(forHTTPHeaderField: "X-First") == "1")
            #expect(request.value(forHTTPHeaderField: "X-Second") == "2")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let endpoint = Endpoint<String, Void>(
            session: session,
            interceptors: [
                HeaderInterceptor(key: "X-First", value: "1"),
                HeaderInterceptor(key: "X-Second", value: "2")
            ],
            api: APIRequest(method: .get, host: "https://example.com", path: "/test")
        )

        _ = try await endpoint.data()
    }

    @Test
    func interceptorOverwritesExistingHeader() async throws {
        let session = MockSession({ request in
            // The interceptor should overwrite the original header
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/plain")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        let endpoint = Endpoint<String, Void>(
            session: session,
            interceptors: [HeaderInterceptor(key: "Accept", value: "text/plain")],
            api: APIRequest(method: .get, host: "https://example.com", path: "/test")
        )

        _ = try await endpoint.data()
    }

    // MARK: - Response Interception

    @Test
    func responseInterceptorTransformsBody() async throws {
        let original = ResponseMock(id: "original", value: 1)
        let replaced = ResponseMock(id: "replaced", value: 99)
        let originalData = try JSONEncoder().encode(original)
        let replacedData = try JSONEncoder().encode(replaced)

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (originalData, response)
        })

        let interceptor = ResponseBodyInterceptor { _ in replacedData }

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            interceptors: [interceptor],
            api: APIRequest(method: .get, host: "https://example.com", path: "/test")
        )

        let result = try await endpoint.data()
        #expect(result.id == "replaced")
        #expect(result.value == 99)
    }

    @Test
    func responseInterceptorLogsStatus() async throws {
        let log = AtomicLog()

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONEncoder().encode(ResponseMock(id: "1", value: 1))
            return (data, response)
        })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            interceptors: [StatusLoggingInterceptor(log: log)],
            api: APIRequest(method: .get, host: "https://example.com", path: "/test")
        )

        _ = try await endpoint.data()
        _ = try await endpoint.data()

        #expect(await log.values == [200, 200])
    }

    @Test
    func responseInterceptorWorksOnDownload() async throws {
        let log = AtomicLog()
        let fileContent = "file content".data(using: .utf8)!

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (fileContent, response)
        })

        let endpoint = Endpoint<URL, Void>(
            session: session,
            interceptors: [StatusLoggingInterceptor(log: log)],
            api: APIRequest(method: .get, host: "https://example.com", path: "/file.zip")
        )

        let url = try await endpoint.download()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(await log.values == [200])
    }

    // MARK: - Both Phases

    @Test
    func interceptorRunsBothPhases() async throws {
        let log = AtomicLog()

        struct DualInterceptor: RequestInterceptor {
            let log: AtomicLog

            func intercept(request: URLRequest) async -> URLRequest {
                await log.append(1)
                return request
            }

            func intercept(response: Response) async -> Response {
                await log.append(2)
                return response
            }
        }

        let session = MockSession({ request in
            let data = try JSONEncoder().encode(ResponseMock(id: "ok", value: 0))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        })

        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            interceptors: [DualInterceptor(log: log)],
            api: APIRequest(method: .get, host: "https://example.com", path: "/test")
        )

        _ = try await endpoint.data()

        // Request phase runs first (1), then response phase (2)
        #expect(await log.values == [1, 2])
    }
}

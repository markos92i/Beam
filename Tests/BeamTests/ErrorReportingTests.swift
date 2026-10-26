//
//  ErrorReportingTests.swift
//  Beam
//
//  Crash reports group non-fatal errors by NSError domain + code, so the domain
//  must identify the route, never the values in it (user ids, document ids…).
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Fixtures

/// Records every report a crash-reporting monitor would send.
private final class CrashRecorder: Monitor {
    struct Report: Sendable {
        let domain: String
        let code: Int
        let info: [String: String]
    }

    static let shared = CrashRecorder()

    private let storage = Mutex<[Report]>([])

    var reports: [Report] { storage.withLock { $0 } }

    func reset() { storage.withLock { $0.removeAll() } }

    func didFail(_ failure: EndpointFailure, context: EndpointContext) {
        guard !failure.isExpected else { return }
        let report = failure.report
        storage.withLock { $0.append(Report(domain: report.domain, code: report.code, info: report.info)) }
    }
}

/// Stands in for app session state (`Defs.shared.userID`).
private enum ReportingDefs {
    static let userID = Mutex(1001)
}

extension APIValues {
    static var currentUserID: Int { ReportingDefs.userID.withLock { $0 } }
}

@API(host: "https://base-url.com", base: "/api/candidates", monitors: [CrashRecorder.shared])
protocol ReportingAPI {
    @Get("/{currentUserID}")
    func profile(params: [URLQueryItem]) async throws(APIError<Void>) -> ResponseMock

    @Get("/{currentUserID}/documents/{documentId}", retry: .none)
    func document(documentId: String, query page: Int?) async throws(APIError<Void>) -> ResponseMock

    @Get("/items/{id}", retry: .none)
    func item(id identifier: Int) async throws(APIError<Void>) -> ResponseMock

    @Get(retry: .none)
    func follow(url: URL) async throws(APIError<Void>) -> ResponseMock

    @Get("/flaky")
    func flaky() async throws(APIError<Void>) -> ResponseMock
}

// MARK: - Tests

@Suite(.serialized)
struct ErrorReportingTests {

    init() { CrashRecorder.shared.reset() }

    private func failing(_ status: Int, counter: AtomicCounter? = nil) -> MockSession {
        MockSession({ (request) throws(URLError) in
            await counter?.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })
    }

    @Test
    func interpolationsAndPlaceholdersBecomeTemplatesInTheDomain() async throws {
        let api = ReportingAPIClient(session: failing(404))
        ReportingDefs.userID.withLock { $0 = 1001 }
        _ = try? await api.document(documentId: "doc-9", query: 2)

        let report = try #require(CrashRecorder.shared.reports.last)
        #expect(report.domain == "GET /api/candidates/{currentUserID}/documents/{documentId} — http(404)")
        // The concrete values stay in userInfo, not in the grouping key.
        #expect(report.info["Path"] == "/api/candidates/1001/documents/doc-9")
        #expect(report.info["Host"] == "https://base-url.com")
    }

    @Test
    func differentUsersAndValuesShareTheSameDomain() async throws {
        let api = ReportingAPIClient(session: failing(404))
        ReportingDefs.userID.withLock { $0 = 1 }
        _ = try? await api.document(documentId: "a", query: nil)
        ReportingDefs.userID.withLock { $0 = 2 }
        _ = try? await api.document(documentId: "b", query: 7)

        let reports = CrashRecorder.shared.reports
        #expect(reports.count == 2)
        #expect(Set(reports.map(\.domain)).count == 1)
        #expect(Set(reports.map(\.code)).count == 1)
    }

    @Test
    func placeholderMatchedByExternalLabelKeepsTheLabelInTheTemplate() async throws {
        _ = try? await ReportingAPIClient(session: failing(500)).item(id: 42)

        let report = try #require(CrashRecorder.shared.reports.last)
        #expect(report.domain == "GET /api/candidates/items/{id} — http(500)")
        #expect(report.info["Path"] == "/api/candidates/items/42")
    }

    @Test
    func aCloudflareStatusIsNamedInTheDomain() async throws {
        _ = try? await ReportingAPIClient(session: failing(522)).item(id: 42)

        let report = try #require(CrashRecorder.shared.reports.last)
        #expect(report.domain == "GET /api/candidates/items/{id} — http(522)")
        #expect(report.info["Status"] == "522")
    }

    /// A code `HTTPStatus` doesn't know is `.undefined` in the error, but the report keeps the number.
    @Test
    func anUnknownStatusKeepsItsNumberInTheReport() async throws {
        _ = try? await ReportingAPIClient(session: failing(599)).item(id: 42)

        let report = try #require(CrashRecorder.shared.reports.last)
        #expect(report.domain == "GET /api/candidates/items/{id} — http(0)")
        #expect(report.info["Status"] == "599")
    }

    @Test
    func retriedErrorsAreReportedOnce() async throws {
        let counter = AtomicCounter()
        _ = try? await ReportingAPIClient(session: failing(503, counter: counter)).flaky()

        #expect(await counter.value == 2) // .standard: 1 retry
        #expect(CrashRecorder.shared.reports.count == 1)
        #expect(CrashRecorder.shared.reports.last?.info["Attempt"] == "1")
    }

    @Test
    func silentErrorsAreNotReported() async throws {
        let session = MockSession({ (_) throws(URLError) in throw URLError(.notConnectedToInternet) })
        _ = try? await ReportingAPIClient(session: session).item(id: 1)
        #expect(CrashRecorder.shared.reports.isEmpty)
    }

    /// Documents current behaviour: routes that differ only in query share a domain.
    @Test
    func routesSharingAPathShareTheDomain() async throws {
        _ = try? await ReportingAPIClient(session: failing(500)).profile(params: [URLQueryItem(name: "expand", value: "a")])

        let report = try #require(CrashRecorder.shared.reports.last)
        #expect(report.domain == "GET /api/candidates/{currentUserID} — http(500)")
    }

    /// An absolute URL has no path of its own: the route's name groups its reports, so
    /// every URL it follows shares one issue.
    @Test
    func absoluteURLIsGroupedByTheRouteName() async throws {
        _ = try? await ReportingAPIClient(session: failing(500)).follow(url: URL(string: "https://cdn.example.com/files/abc?sig=1")!)
        _ = try? await ReportingAPIClient(session: failing(500)).follow(url: URL(string: "https://other.example.com/x")!)

        let reports = CrashRecorder.shared.reports
        #expect(reports.map(\.domain) == ["GET ReportingAPI.follow — http(500)", "GET ReportingAPI.follow — http(500)"])
        #expect(reports.first?.info["Host"] == "https://cdn.example.com/files/abc?sig=1")
    }

    /// A request built by hand without a template is grouped by its path, not by an empty one.
    @Test
    func aHandBuiltRequestIsGroupedByItsPath() async throws {
        let endpoint = Endpoint<ResponseMock, Void>(
            session: failing(404),
            monitors: [CrashRecorder.shared],
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/reports")
        )
        _ = try? await endpoint.data()

        let report = try #require(CrashRecorder.shared.reports.last)
        #expect(report.domain == "GET /reports — http(404)")
    }
}

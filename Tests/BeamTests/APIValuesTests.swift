//
//  APIValuesTests.swift
//  Beam
//
//  `{name}` placeholders filled by parameters or `APIValues`, `query:` templates,
//  `APIError.missingValue` and per-segment percent-encoding.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Fixtures

/// Stands in for app session state that the `APIValues` properties read.
private enum Session {
    static let userID = Mutex<Int?>(7)
    static let locale = Mutex<String?>("es")
}

extension APIValues {
    static var sessionUserID: Int? { Session.userID.withLock { $0 } }
    static var sessionLocale: String? { Session.locale.withLock { $0 } }
}

/// Records sent requests and the reports sent through `CrashProtocol`.
private final class Probe: Monitor {
    private let requests = Mutex<[URLRequest]>([])
    private let reports = Mutex<[String]>([])

    var sent: [URLRequest] { requests.withLock { $0 } }
    var reportedDomains: [String] { reports.withLock { $0 } }

    func reset() {
        requests.withLock { $0.removeAll() }
        reports.withLock { $0.removeAll() }
    }

    func didFail(_ failure: EndpointFailure, context: EndpointContext) {
        guard !failure.isExpected else { return }
        reports.withLock { $0.append(failure.report.domain) }
    }

    func session() -> MockSession {
        let body = try! JSONEncoder().encode(ResponseMock(id: "1", value: 1))
        return MockSession({ [self] (request) throws(URLError) in
            requests.withLock { $0.append(request) }
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
    }

    static let shared = Probe()
}

@API(host: "https://base-url.com/api", base: "/v1", monitors: [Probe.shared])
protocol ValuesAPI {
    @Get("/users/{sessionUserID}/items/{id}", retry: .none)
    func item(id: String) async throws(APIError<Void>) -> ResponseMock

    @Get("/search", query: ["$expand": "a,b", "lang": "{sessionLocale}", "page": "{page}"], retry: .none)
    func search(page: Int?, query term: String) async throws(APIError<Void>) -> ResponseMock
}

// MARK: - Tests

@Suite(.serialized)
struct APIValuesTests {

    init() {
        Probe.shared.reset()
        Session.userID.withLock { $0 = 7 }
        Session.locale.withLock { $0 = "es" }
    }

    private var api: ValuesAPIClient { ValuesAPIClient(session: Probe.shared.session()) }

    @Test
    func pathPlaceholdersComeFromAPIValuesAndParameters() async throws {
        _ = try await api.item(id: "42")
        #expect(Probe.shared.sent.last?.url?.absoluteString == "https://base-url.com/api/v1/users/7/items/42")

        Session.userID.withLock { $0 = 8 }
        _ = try await api.item(id: "42") // read on every request
        #expect(Probe.shared.sent.last?.url?.absoluteString == "https://base-url.com/api/v1/users/8/items/42")
    }

    @Test
    func missingAPIValueFailsLocallyAndIsReported() async {
        Session.userID.withLock { $0 = nil }
        do {
            _ = try await api.item(id: "42")
            Issue.record("Should have thrown")
        } catch {
            #expect(error.name == "missingValue(sessionUserID)")
        }
        #expect(Probe.shared.sent.isEmpty)
        #expect(Probe.shared.reportedDomains == ["GET /v1/users/{sessionUserID}/items/{id} — missingValue(sessionUserID)"])
    }

    @Test
    func placeholderValuesAreEncodedAsSingleSegments() async throws {
        _ = try await api.item(id: "a/b c?")
        #expect(Probe.shared.sent.last?.url?.absoluteString == "https://base-url.com/api/v1/users/7/items/a%2Fb%20c%3F")
    }

    @Test
    func routeQueryKeepsOrderAndOmitsNilParameters() async throws {
        _ = try await api.search(page: 2, query: "swift")
        #expect(Probe.shared.sent.last?.url?.query() == "$expand=a,b&lang=es&page=2&term=swift")

        _ = try await api.search(page: nil, query: "swift")
        #expect(Probe.shared.sent.last?.url?.query() == "$expand=a,b&lang=es&term=swift")
    }

    @Test
    func missingAPIValueInQueryFailsLocally() async {
        Session.locale.withLock { $0 = nil }
        do {
            _ = try await api.search(page: 1, query: "swift")
            Issue.record("Should have thrown")
        } catch {
            #expect(error == .missingValue("sessionLocale"))
            #expect(error.name == "missingValue(sessionLocale)")
        }
        #expect(Probe.shared.sent.isEmpty)
    }
}

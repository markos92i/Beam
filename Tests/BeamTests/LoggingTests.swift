//
//  LoggingTests.swift
//  Beam
//

import Foundation
import Logy
import Testing
@testable import Beam

@Suite
struct LoggingTests {

    @Test
    func theAPILogLevelAppliesToRequestAndResponseLogs() {
        let endpoint = Endpoint<ResponseMock, Void>(
            session: MockSession(),
            logLevel: .error,
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/a")
        )
        let call = endpoint.call()
        #expect(call.client.log.level == .error)
        #expect(call.log.level == .error)
    }

    @Test
    func eachKindOfEventGoesToItsChannel() {
        let url = URL(string: "https://apis.randstad.es/a")!
        #expect(LogEvent.request(id: "a", method: "GET", url: url, headers: nil, body: nil).channel.category == "http")
        #expect(LogEvent.wsPing(id: "a").channel.category == "websocket")
        #expect(LogEvent.auth(type: "TokenAuth", name: "api", detail: "x").channel.category == "auth")
        #expect(LogEvent.codingFailed(id: "a", what: "x", detail: "y").channel.category == "error")
        #expect(LogEvent.wsPing(id: "a").channel.subsystem === LogSubsystem.beam)
        #expect(LogSubsystem.beam.name == "com.beam")
    }

    @Test
    func aBackgroundTransferNobodyAwaitsIsLoggedWithItsRoute() {
        let succeeded = LogEvent.backgroundFinished(id: "video-42", method: "POST", path: "/{userID}/documents", status: 201, failure: nil)
        let failed = LogEvent.backgroundFinished(id: "video-42", method: "POST", path: "/{userID}/documents", status: nil, failure: "The network connection was lost.")

        #expect(succeeded.rendered(bodies: false).contains("video-42"))
        #expect(succeeded.rendered(bodies: false).contains("/{userID}/documents"))
        #expect(succeeded.level == .info)
        #expect(failed.rendered(bodies: false).contains("The network connection was lost."))
        #expect(failed.level == .warning)
        #expect(LogEvent.backgroundFinished(id: "x", method: "GET", path: "/", status: 404, failure: nil).level == .warning)
    }

    @Test
    func aDownloadIsLoggedWithItsSuggestedNameAndSize() {
        let event = LogEvent.response(id: "a1", status: 200, headers: [:], body: .file(name: "report.pdf", bytes: 2048), elapsed: .zero)
        let rendered = event.rendered(bodies: false)
        #expect(rendered.contains("report.pdf"))
        #expect(rendered.contains(2048.byteFormatted))
    }

    /// Bodies are shown at debug level; an error response always shows its own.
    @Test
    func bodiesAreShownAtDebugLevelAndAlwaysForErrorResponses() {
        func response(_ status: Int, bodies: Bool) -> String {
            LogEvent.response(id: "a1", status: status, headers: [:], body: .data(Data(#"{"name":"Ana"}"#.utf8)), elapsed: .zero)
                .rendered(bodies: bodies)
        }
        #expect(response(200, bodies: true).contains("Ana"))
        #expect(!response(200, bodies: false).contains("Ana"))
        #expect(response(404, bodies: false).contains("Ana"))
    }

    /// A request and its response line up by column, whatever the length of the method.
    @Test
    func aRequestAndItsResponseLineUpByColumn() {
        let request = LogEvent.request(id: "A1F3", method: "DELETE", url: URL(string: "https://apis.randstad.es/a")!, headers: nil, body: nil)
            .rendered(bodies: false)
        let response = LogEvent.response(id: "A1F3", status: 404, headers: [:], body: .none, elapsed: .zero)
            .rendered(bodies: false)
        func start(of text: String, in log: String) -> Int {
            let line = log.prefix { $0 != "\n" }
            return line.distance(from: line.startIndex, to: line.range(of: text)!.lowerBound)
        }
        #expect(start(of: "DELETE", in: request) == start(of: "404", in: response))
        #expect(start(of: "􀎠", in: request) == start(of: "􀐫", in: response))
        #expect(!request.contains("\t"))
    }

    @Test
    func aRejectedCredentialIsLoggedAtDebugLevel() {
        #expect(LogEvent.auth(type: "StaticAuth", name: "api", detail: "rejected", level: .debug).level == .debug)
        #expect(LogEvent.auth(type: "TokenAuth", name: "api", detail: "refreshing").level == .info)
    }
}

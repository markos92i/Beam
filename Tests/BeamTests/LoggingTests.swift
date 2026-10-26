//
//  LoggingTests.swift
//  Beam
//

import Foundation
import os
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
        #expect(call.client.log.effectiveLevel == .error)
        #expect(call.log.effectiveLevel == .error)
    }

    @Test
    func levelsMapToTheSystemTypesAsOSLoggerDoes() {
        #expect(LogLevel.warning.osLogType == .error)
        #expect(LogLevel.error.osLogType == .error)
        #expect(LogLevel.info.osLogType == .info)
        #expect(LogLevel.debug.osLogType == .debug)
    }

    @Test
    func aBackgroundTransferNobodyAwaitsIsLoggedWithItsRoute() {
        let succeeded = LogEvent.backgroundFinished(id: "video-42", method: "POST", path: "/{userID}/documents", status: 201, failure: nil)
        let failed = LogEvent.backgroundFinished(id: "video-42", method: "POST", path: "/{userID}/documents", status: nil, failure: "The network connection was lost.")

        #expect(succeeded.rendered(bodies: false).contains("video-42"))
        #expect(succeeded.rendered(bodies: false).contains("/{userID}/documents"))
        #expect(succeeded.meta.level == .info)
        #expect(failed.rendered(bodies: false).contains("The network connection was lost."))
        #expect(failed.meta.level == .warning)
        #expect(LogEvent.backgroundFinished(id: "x", method: "GET", path: "/", status: 404, failure: nil).meta.level == .warning)
    }

    @Test
    func aDownloadIsLoggedWithItsSuggestedNameAndSize() {
        let event = LogEvent.response(id: "a1", status: 200, headers: [:], body: .file(name: "report.pdf", bytes: 2048), start: Date())
        let rendered = event.rendered(bodies: false)
        #expect(rendered.contains("report.pdf"))
        #expect(rendered.contains(2048.byteFormatted))
    }

    /// Bodies are shown at debug level; an error response always shows its own.
    @Test
    func bodiesAreShownAtDebugLevelAndAlwaysForErrorResponses() {
        func response(_ status: Int, bodies: Bool) -> String {
            LogEvent.response(id: "a1", status: status, headers: [:], body: .data(Data(#"{"name":"Ana"}"#.utf8)), start: Date())
                .rendered(bodies: bodies)
        }
        #expect(response(200, bodies: true).contains("Ana"))
        #expect(!response(200, bodies: false).contains("Ana"))
        #expect(response(404, bodies: false).contains("Ana"))
        #expect(BeamLogger(level: .debug).logs(.debug, global: .warning))
        #expect(!BeamLogger(level: .info).logs(.debug, global: .debug))
    }

    /// A global `.off` silences every log, also an API's with its own level.
    @Test
    func aGlobalOffSilencesAnAPIWithItsOwnLevel() {
        let api = BeamLogger(level: .debug)
        #expect(api.logs(.info, global: .error))
        #expect(!api.logs(.error, global: .off))
        #expect(!BeamLogger().logs(.error, global: .off))
        #expect(!BeamLogger(level: .off).logs(.error, global: .debug))
    }

    /// A request and its response line up by column, whatever the length of the method.
    @Test
    func aRequestAndItsResponseLineUpByColumn() {
        let request = LogEvent.request(id: "A1F3", method: "DELETE", url: URL(string: "https://apis.randstad.es/a")!, headers: nil, body: nil)
            .rendered(bodies: false)
        let response = LogEvent.response(id: "A1F3", status: 404, headers: [:], body: .none, start: Date())
            .rendered(bodies: false)
        func start(of text: String, in log: String) -> Int {
            let line = log.prefix { $0 != "\n" }
            return line.distance(from: line.startIndex, to: line.range(of: text)!.lowerBound)
        }
        #expect(start(of: "DELETE", in: request) == start(of: "404", in: response))
        #expect(start(of: "􀎠", in: request) == start(of: "􀐫", in: response))
        #expect(!request.contains("\t"))
    }

    /// A value longer than its column pushes the next one, which never gets closer than the gap.
    @Test
    func aLongColumnKeepsTheGap() {
        #expect(LogColumns.align("a\tb") == "a" + String(repeating: " ", count: 6 + LogColumns.gap) + "b")
        #expect(LogColumns.align("abcdefghij\tb") == "abcdefghij" + String(repeating: " ", count: LogColumns.gap) + "b")
        #expect(LogColumns.align("􀁶 A1F3\tb") == "􀁶 A1F3" + String(repeating: " ", count: LogColumns.gap) + "b")
        #expect(LogColumns.align("a\t") == "a")
    }

    @Test
    func aRejectedCredentialIsLoggedAtDebugLevel() {
        #expect(LogEvent.auth(type: "StaticAuth", name: "api", detail: "rejected", level: .debug).meta.level == .debug)
        #expect(LogEvent.auth(type: "TokenAuth", name: "api", detail: "refreshing").meta.level == .info)
    }
}

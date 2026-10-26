//
//  EndpointMockTests.swift
//  Beam
//
//  An endpoint's mock answers every call of the endpoint — direct or through a handle —
//  instead of the network. `@API`'s `on<Route>` closures become this mock.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

@Suite(.timeLimit(.minutes(1)))
struct EndpointMockTests {
    private final class Counter: Sendable {
        let value = Mutex(0)
    }

    /// How many requests reached the session.
    private let reached = Counter()
    private var requests: Int { reached.value.withLock { $0 } }

    private func api() -> APIConfiguration {
        let session = MockSession({ [reached] (request) throws(URLError) in
            reached.value.withLock { $0 += 1 }
            return (json(ResponseMock(id: "network", value: 0)), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        return APIConfiguration(host: "https://base-url.com", session: session, config: RequestConfig(retry: .none))
    }

    private func mocked() -> Endpoint<ResponseMock, Void> {
        let api = api()
        return Endpoint(api, request: api.request(.post, "/items"))
            .mocking(.init { resume in ResponseMock(id: "mock", value: resume?.count ?? -1) })
    }

    @Test
    func theMockAnswersTheDirectCalls() async throws {
        #expect(try await mocked().data().id == "mock")
        #expect(try await mocked().upload(.body(.data(Data()))).id == "mock")
        #expect(requests == 0)
    }

    @Test
    func theMockAnswersTheHandles() async throws {
        #expect(try await mocked().uploadTask(.body(.data(Data()))).start().id == "mock")
        #expect(try await mocked().backgroundUploadTask(on: backgroundTestSession, .body(.data(Data()))).start(id: "doc").id == "mock")
        #expect(requests == 0)
    }

    @Test
    func theMockGetsTheResumeDataOfTheCall() async throws {
        let resume = Data("resume".utf8)
        #expect(try await mocked().upload(.body(.data(Data())), resumeFrom: resume).value == 6)
        #expect(try await mocked().uploadTask(.body(.data(Data()))).start(resumeFrom: resume).value == 6)
        #expect(try await mocked().uploadTask(.body(.data(Data()))).start().value == -1)
    }

    @Test
    func aDownloadsMockAnswersEveryPath() async throws {
        let api = api()
        let file = URL(fileURLWithPath: "/mock/file")
        let download = Endpoint<URL, Void>(api, request: api.request(.get, "/file")).mocking(.init { _ in file })
        #expect(try await download.download() == file)
        #expect(try await download.downloadTask().start() == file)
        #expect(try await download.backgroundDownloadTask(on: backgroundTestSession).start(id: "doc") == file)
        #expect(requests == 0)
    }

    @Test
    func withoutAMockTheNetworkAnswers() async throws {
        #expect(try await mocked().mocking(nil).data().id == "network")
        #expect(requests == 1)
    }

    /// A mocked call is cancelled like a real one, also from a handle.
    @Test
    func aHandleCancelsItsMock() async throws {
        let api = api()
        let (started, didStart) = AsyncStream.makeStream(of: Void.self)
        let slow = Endpoint<ResponseMock, Void>(api, request: api.request(.post, "/items")).mocking(.init { _ in
            didStart.yield()
            try? await Task.sleep(for: .seconds(30))
            return ResponseMock(id: "late", value: 0)
        })
        let handle = slow.uploadTask(.body(.data(Data())))
        let call = Task { () -> APIError<Void>? in
            do throws(APIError<Void>) { _ = try await handle.start(); return nil } catch { return error }
        }
        for await _ in started { break }
        await handle.cancel()
        #expect(await call.value.map { $0 == .cancelled } == true)
    }
}

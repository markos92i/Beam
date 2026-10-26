//
//  BackgroundTransferTests.swift
//  Beam
//
//  Transfers on a real background session: uploads (in-memory and file bodies),
//  downloads, handles, attaching to a transfer in flight, unclaimed results,
//  cancellation with resume data and SSL pinning.
//
//  ⚠️ Requires internet.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Fixtures

/// The run's background session: one per identifier, alive for the whole process,
/// as in an app. Releasing background sessions while others transfer breaks them.
let backgroundTestSession = Session(.background("com.beam.test.background.\(UUID().uuidString)")) {
    $0.sessionSendsLaunchEvents = false
}

/// A background session whose trust policy rejects every server.
private let rejectingBackgroundSession = Session(
    .background("com.beam.test.pinning.\(UUID().uuidString)"),
    trustPolicy: RejectAllPolicy()
) { $0.sessionSendsLaunchEvents = false }

private struct RejectAllPolicy: TransportTrustPolicy {
    func evaluate(challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.cancelAuthenticationChallenge, nil)
    }
}

struct EchoBody: Codable, Sendable {
    let content: String
}

struct EchoResponse: Codable, Sendable {
    let json: EchoBody?
}

private func endpoint<Success: Decodable & SendableMetatype>(
    _ method: HTTPMethod = .get,
    host: String = "https://postman-echo.com",
    path: String,
    body: HTTPBody? = nil
) -> Endpoint<Success, Void> {
    Endpoint(
        config: RequestConfig(retry: .none),
        api: APIRequest(method: method, host: host, path: path, pathTemplate: path, body: body)
    )
}

/// The session's tasks in flight with Beam's id `id`.
private func tasks(withID id: String, in session: Session<Background>) async -> [URLSessionTask] {
    await session.allTasks.filter {
        BackgroundTaskDescription($0.taskDescription)?.id == id && ($0.state == .running || $0.state == .suspended)
    }
}

/// A generated client with a background session: its transfer routes get
/// `<route>BackgroundTask(…)` handles.
@API(host: "https://postman-echo.com", background: backgroundTestSession, config: RequestConfig(retry: .none))
protocol BackgroundEchoAPI {
    @Post("/post", task: .upload)
    func upload(body: HTTPBody) async throws(APIError<Void>) -> EchoResponse

    @Get("/get", task: .download)
    func download() async throws(APIError<Void>) -> URL

    @Post("/post", task: .download)
    func downloadPosting(body: EchoBody) async throws(APIError<Void>) -> URL
}

// MARK: - Downloads with a body

/// postman-echo answers with what it received: the downloaded file holds the request body.
@Suite("Downloads with a body", .serialized, .tags(.network), .timeLimit(.minutes(2)))
struct DownloadBodyTests {
    private let api = BackgroundEchoAPIClient()

    private func echoed(_ file: URL) throws -> String? {
        defer { try? FileManager.default.removeItem(at: file) }
        return try JSONDecoder().decode(EchoResponse.self, from: Data(contentsOf: file)).json?.content
    }

    @Test
    func theDirectCallSendsIt() async throws {
        #expect(try echoed(await api.downloadPosting(body: EchoBody(content: "direct"))) == "direct")
    }

    @Test
    func theHandleSendsIt() async throws {
        #expect(try echoed(await api.downloadPostingTask(body: EchoBody(content: "handle")).start()) == "handle")
    }

    @Test
    func theBackgroundHandleSendsIt() async throws {
        let posting = api.downloadPostingBackgroundTask(body: EchoBody(content: "background"))
        #expect(try echoed(await posting.start(id: UUID().uuidString)) == "background")
    }
}

// MARK: - Transfers

@Suite("Background transfers", .serialized, .tags(.network), .timeLimit(.minutes(2)))
struct BackgroundTransferTests {
    private let session = backgroundTestSession

    @Test
    func downloads() async throws {
        let get: Endpoint<URL, Void> = endpoint(path: "/get")
        let url = try await get.backgroundDownloadTask(on: session).start(id: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try !Data(contentsOf: url).isEmpty)
    }

    /// Background sessions only upload files: the body is written to a temporary file.
    @Test
    func uploadsAnInMemoryBody() async throws {
        let body = json(EchoBody(content: "in-memory"))
        let response: EchoResponse = try await endpoint(.post, path: "/post")
            .backgroundUploadTask(on: session, .body(.data(body, contentType: .json))).start(id: UUID().uuidString)
        #expect(response.json?.content == "in-memory")
    }

    @Test
    func uploadsAFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try json(EchoBody(content: "from-file")).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let echo: Endpoint<EchoResponse, Void> = Endpoint(
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .post, host: "https://postman-echo.com", path: "/post", headers: ["Content-Type": "application/json"])
        )
        let response = try await echo.backgroundUploadTask(on: session, .file(file)).start(id: UUID().uuidString)
        #expect(response.json?.content == "from-file")
    }

    @Test
    func handlesRunOnTheBackgroundSession() async throws {
        // httpbin: postman-echo has no slow POST, and the task must still run when checked.
        let upload = (endpoint(.post, host: "https://httpbin.org", path: "/delay/1") as Endpoint<EchoResponse, Void>).backgroundUploadTask(on: session, .body(.data(json(EchoBody(content: "handle")), contentType: .json)))
        let id = UUID().uuidString
        let uploading = Task { try await upload.start(id: id) }
        // The upload's task is the background session's.
        let deadline = ContinuousClock.now + .seconds(5)
        while await tasks(withID: id, in: session).isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await !tasks(withID: id, in: session).isEmpty)
        _ = try await uploading.value

        let download = endpoint(path: "/get").backgroundDownloadTask(on: session)
        let url = try await download.start(id: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try !Data(contentsOf: url).isEmpty)
    }

    @Test
    func generatedBackgroundHandlesWork() async throws {
        let api = BackgroundEchoAPIClient()
        let echoed = try await api.uploadBackgroundTask(body: .data(json(EchoBody(content: "generated")), contentType: .json))
            .start(id: UUID().uuidString)
        #expect(echoed.json?.content == "generated")

        let url = try await api.downloadBackgroundTask().start(id: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try !Data(contentsOf: url).isEmpty)
    }

    // MARK: - Attaching

    /// Two starts with the same id while the first is in flight: one transfer, both get it.
    @Test
    func startingAgainWithTheSameIDAttachesToTheTransferInFlight() async throws {
        let id = UUID().uuidString
        let slow: Endpoint<URL, Void> = endpoint(path: "/delay/1")

        async let first = slow.backgroundDownloadTask(on: session).start(id: id)
        async let second = slow.backgroundDownloadTask(on: session).start(id: id)

        try await Task.sleep(for: .milliseconds(400))
        #expect(await tasks(withID: id, in: session).count == 1)

        let (a, b) = try await (first, second)
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(try Data(contentsOf: a) == Data(contentsOf: b))
    }

    @Test
    func differentIDsAreDifferentTransfers() async throws {
        let (first, second) = (UUID().uuidString, UUID().uuidString)
        let slow: Endpoint<URL, Void> = endpoint(path: "/delay/1")

        async let a = slow.backgroundDownloadTask(on: session).start(id: first)
        async let b = slow.backgroundDownloadTask(on: session).start(id: second)

        try await Task.sleep(for: .milliseconds(400))
        #expect(await tasks(withID: first, in: session).count == 1)
        #expect(await tasks(withID: second, in: session).count == 1)
        _ = try await (a, b)
    }

    /// A transfer that finished with nobody awaiting it (as after a relaunch): starting
    /// again with its id takes that result instead of transferring again.
    @Test
    func startingAgainTakesAnUnclaimedResult() async throws {
        let id = UUID().uuidString
        let slow: Endpoint<URL, Void> = endpoint(path: "/delay/2")
        let key = BackgroundTaskKey(id: id, method: "GET", path: "/delay/2")

        // Start the transfer without awaiting it, and let it finish unclaimed.
        let orphan = session.makeDownloadTask(URLRequest(url: URL(string: "https://postman-echo.com/delay/2")!), key: key)
        orphan.resume()
        let deadline = ContinuousClock.now + .seconds(20)
        while orphan.state != .completed, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(orphan.state == .completed)
        try await Task.sleep(for: .milliseconds(200)) // let the delegate store the result

        let clock = ContinuousClock()
        let start = clock.now
        let url = try await slow.backgroundDownloadTask(on: session).start(id: id)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(clock.now - start < .seconds(1), "It transferred again instead of taking the result")
        #expect(try !Data(contentsOf: url).isEmpty)
    }

    // MARK: - Cancellation and pinning

    @Test
    func cancellingADownloadProducesResumeData() async throws {
        let big: Endpoint<URL, Void> = endpoint(host: "https://proof.ovh.net", path: "/files/100Mb.dat")
        let handle = big.backgroundDownloadTask(on: session)

        let job = Task { () -> Result<URL, APIError<Void>> in
            do throws(APIError<Void>) { return .success(try await handle.start(id: UUID().uuidString)) } catch { return .failure(error) }
        }
        try await Task.sleep(for: .milliseconds(800))
        let resumeData = await handle.cancel()

        guard case .failure(let error) = await job.value else {
            Issue.record("The download finished before it could be cancelled")
            return
        }
        #expect(error == .cancelled)
        #expect(resumeData?.isEmpty == false)
    }

    /// The trust policy applies to background transfers too: a rejected server is an
    /// SSL error, not a cancellation.
    @Test
    func aBackgroundSessionAppliesItsTrustPolicy() async {
        let apple: Endpoint<URL, Void> = endpoint(host: "https://www.apple.com", path: "/")
        do {
            _ = try await apple.backgroundDownloadTask(on: rejectingBackgroundSession).start(id: UUID().uuidString)
            Issue.record("The trust policy should have rejected the server")
        } catch {
            #expect(error == .sslError, "Got \(error)")
        }
    }
}

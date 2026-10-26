//
//  TransferStoreTests.swift
//  Beam
//
//  Background transfers that finish with nobody awaiting them are kept on disk until
//  the app removes them, so a later launch still finds them.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - The store on its own

@Suite
struct TransferStoreTests {
    private let store = TransferStore(root: FileManager.default.temporaryDirectory.appending(path: "beam-store-\(UUID().uuidString)"))
    private static let key = BackgroundTaskKey(id: "doc-1", method: "GET", path: "/{userID}/documents/{id}")

    /// Writes a stored transfer the way `save` leaves it.
    private func stored(
        _ kind: TransferStore.Kind = .download,
        file: (name: String, content: String)? = ("report.pdf", "pdf"),
        status: Int? = 200,
        failure: TransferStore.Failure? = nil,
        key: BackgroundTaskKey = key,
        at date: Date = Date()
    ) throws -> String {
        let id = UUID().uuidString
        let folder = store.root.appending(path: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let file { try Data(file.content.utf8).write(to: folder.appending(path: file.name)) }
        let record = TransferStore.Record(
            v: 1, kind: kind, taskDescription: BackgroundTaskDescription(key).encoded,
            url: URL(string: "https://api.example.com/7/documents/1"), method: key.method,
            status: status, headers: ["Content-Type": "application/pdf"],
            file: file?.name, failure: failure, finishedAt: date
        )
        try JSONEncoder().encode(record).write(to: folder.appending(path: "record.json"))
        return id
    }

    @Test
    func aStoredDownloadIsRebuiltWithItsFileRouteAndResponse() throws {
        let id = try stored()
        defer { store.removeAll() }

        let result = store.result(of: try #require(store.entries().first))
        guard case .downloaded(let file) = result.outcome else {
            Issue.record("Expected a download, got \(result.outcome)")
            return
        }
        #expect(file == store.root.appending(path: id).appending(path: "report.pdf"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "pdf")
        #expect(result.response?.statusCode == 200)
        #expect(result.response?.value(forHTTPHeaderField: "Content-Type") == "application/pdf")
        #expect(BackgroundTaskDescription(result.taskDescription)?.key == Self.key)
        #expect(result.storeID == id)
    }

    @Test
    func aStoredUploadIsRebuiltWithTheServersResponse() throws {
        _ = try stored(.upload, file: ("response", #"{"id":"doc"}"#), status: 201)
        defer { store.removeAll() }

        guard case .uploaded(let data) = store.result(of: try #require(store.entries().first)).outcome else {
            Issue.record("Expected an upload")
            return
        }
        #expect(data == Data(#"{"id":"doc"}"#.utf8))
    }

    /// The record keeps the file's name, not its path: the app's container moves on
    /// reinstalls and restores.
    @Test
    func theFileIsFoundAfterTheContainerMoves() throws {
        _ = try stored()
        let moved = TransferStore(root: FileManager.default.temporaryDirectory.appending(path: "beam-store-\(UUID().uuidString)"))
        try FileManager.default.moveItem(at: store.root, to: moved.root)
        defer { moved.removeAll() }

        guard case .downloaded(let file) = moved.result(of: try #require(moved.entries().first)).outcome else {
            Issue.record("Expected a download")
            return
        }
        #expect(file.path().hasPrefix(moved.root.path()))
        #expect(FileManager.default.fileExists(atPath: file.path()))
    }

    @Test
    func aTransferThatFailedBeforeAResponseKeepsItsReason() throws {
        _ = try stored(file: nil, status: nil, failure: .network(code: URLError.Code.networkConnectionLost.rawValue))
        defer { store.removeAll() }

        guard case .failed(let error) = store.result(of: try #require(store.entries().first)).outcome else {
            Issue.record("Expected a failure")
            return
        }
        #expect(APIError<Void>(error) == .noConnection)
    }

    @Test
    func entriesAreOldestFirstAndHalfWrittenFoldersAreIgnored() throws {
        let newer = try stored(at: Date())
        let older = try stored(at: Date(timeIntervalSinceNow: -60))
        try FileManager.default.createDirectory(at: store.root.appending(path: "half-written"), withIntermediateDirectories: true)
        defer { store.removeAll() }

        #expect(store.entries().map(\.id) == [older, newer])
    }

    @Test
    func takingADownloadMovesItsFileOutAndForgetsIt() throws {
        _ = try stored()
        defer { store.removeAll() }

        let taken = try #require(store.take(Self.key))
        guard case .downloaded(let file) = taken.outcome else {
            Issue.record("Expected a download")
            return
        }
        defer { FileUtils.discard(file) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "pdf")
        #expect(!file.path().hasPrefix(store.root.path()))
        #expect(taken.storeID == nil)
        #expect(store.entries().isEmpty)
        #expect(store.take(Self.key) == nil)
    }

    @Test
    func removingDeletesTheRecordAndTheFile() throws {
        let first = try stored()
        _ = try stored(key: BackgroundTaskKey(id: "doc-2", method: "GET", path: "/x"))

        store.remove(first)
        #expect(store.entries().count == 1)
        #expect(!FileManager.default.fileExists(atPath: store.root.appending(path: first).path()))

        store.removeAll()
        #expect(store.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.root.path()))
    }
}

// MARK: - A real background session

/// A background session of its own: these tests remove everything it stored.
/// Static, like every background session in tests (releasing one cancels its transfers).
private let storeTestSession = Session(.background("com.beam.test.store.\(UUID().uuidString)"))

@Suite("Finished transfers on disk", .serialized, .tags(.network), .timeLimit(.minutes(2)))
struct FinishedTransfersTests {
    private let session = storeTestSession

    /// What `finished()` hands out right now — what is stored — without waiting for more.
    private func stored() async -> [FinishedTransfer] {
        let transfers = Mutex<[FinishedTransfer]>([])
        let listening = Task {
            for await transfer in session.finished() { transfers.withLock { $0.append(transfer) } }
        }
        try? await Task.sleep(for: .milliseconds(200))
        listening.cancel()
        return transfers.withLock { $0 }
    }

    private func key(_ id: String, _ method: String, _ path: String) -> BackgroundTaskKey {
        BackgroundTaskKey(id: id, method: method, path: path)
    }

    /// Waits until the transfer `id` finished unclaimed and was kept.
    private func waitStored(_ id: String) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while session.sessionDelegate.store?.entries().contains(where: { BackgroundTaskDescription($0.record.taskDescription)?.id == id }) != true,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Downloads `path` without awaiting it, as when the app is not running.
    private func downloadUnclaimed(_ path: String, id: String) async throws {
        let task = session.makeDownloadTask(URLRequest(url: URL(string: "https://postman-echo.com\(path)")!), key: key(id, "GET", path))
        task.resume()
        try await waitStored(id)
    }

    @Test
    func aDownloadNobodyAwaitedIsHandedOutWithItsFileUntilRemoved() async throws {
        defer { session.removeAllFinishedTransfers() }
        try await downloadUnclaimed("/get", id: "listed")

        let download = try #require(await stored().first { $0.id == "listed" })
        #expect(download.method == .get)
        #expect(download.pathTemplate == "/get")
        guard case .downloaded(let file) = download.outcome else {
            Issue.record("Expected a download, got \(download.outcome)")
            return
        }
        #expect(try !Data(contentsOf: file).isEmpty)

        // Kept on disk: a new store on the same folder — the next launch — finds it.
        let root = try #require(session.sessionDelegate.store?.root)
        #expect(TransferStore(root: root).entries().count == 1)
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        // Receiving it doesn't remove it; removing does, file included.
        #expect(await stored().count == 1)
        session.remove(download)
        #expect(await stored().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path()))
    }

    @Test
    func anUploadNobodyAwaitedIsHandedOutWithTheServersResponse() async throws {
        defer { session.removeAllFinishedTransfers() }
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try json(EchoBody(content: "unclaimed")).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var request = URLRequest(url: URL(string: "https://postman-echo.com/post")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let task = session.makeUploadTask(request, fromFile: file, key: key("uploaded", "POST", "/post"))
        task.resume()
        try await waitStored("uploaded")

        let upload = try #require(await stored().first { $0.id == "uploaded" })
        guard case .uploaded(let data) = upload.outcome else {
            Issue.record("Expected an upload, got \(upload.outcome)")
            return
        }
        #expect(try JSONDecoder().decode(EchoResponse.self, from: data).json?.content == "unclaimed")
    }

    @Test
    func aFailedDownloadIsHandedOutWithItsStatusAndErrorBody() async throws {
        defer { session.removeAllFinishedTransfers() }
        try await downloadUnclaimed("/status/404", id: "missing")

        let download = try #require(await stored().first { $0.id == "missing" })
        guard case .failed(let error) = download.outcome else {
            Issue.record("Expected a failure, got \(download.outcome)")
            return
        }
        #expect(error == .http(status: .notFound))
        #expect(download.body != nil)
    }

    /// A `start(id:)` on the same route takes it instead of downloading again, and it
    /// is no longer handed out.
    @Test
    func startingAgainTakesTheStoredTransfer() async throws {
        defer { session.removeAllFinishedTransfers() }
        try await downloadUnclaimed("/get", id: "claimed")

        let endpoint = Endpoint<URL, Void>(config: RequestConfig(retry: .none), api: APIRequest(method: .get, host: "https://postman-echo.com", path: "/get", pathTemplate: "/get"))
        let file = try await endpoint.backgroundDownloadTask(on: session).start(id: "claimed")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        #expect(try !Data(contentsOf: file).isEmpty)
        #expect(await stored().isEmpty)
    }

    /// The app cancelled it itself — e.g. on logout, right after clearing the store —
    /// so it isn't kept: it would be left for the next user.
    @Test
    func aCancelledTransferIsNotKept() async throws {
        defer { session.removeAllFinishedTransfers() }
        let task = session.makeDownloadTask(URLRequest(url: URL(string: "https://postman-echo.com/delay/5")!), key: key("cancelled", "GET", "/delay/5"))
        task.resume()
        task.cancel()
        let deadline = ContinuousClock.now + .seconds(10)
        while task.state != .completed, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(300)) // let the delegate handle the completion

        #expect(!(await stored()).contains { $0.id == "cancelled" })
    }

    @Test
    func removingAllClearsEverything() async throws {
        try await downloadUnclaimed("/get", id: "a")
        try await downloadUnclaimed("/get", id: "b")
        #expect(await stored().count == 2)

        session.removeAllFinishedTransfers()
        #expect(await stored().isEmpty)
    }
}

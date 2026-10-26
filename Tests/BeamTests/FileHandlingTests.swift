//
//  FileHandlingTests.swift
//  Beam
//
//  Files Beam reads and keeps: files to upload must exist before anything is sent,
//  and downloads are moved — not copied — into a folder of their own.
//

import Foundation
import Testing
@testable import Beam

/// An upload route with a file, on an API with a background session.
@API(host: "https://base-url.com", background: backgroundTestSession)
protocol FileUploadAPI {
    @Put("/raw", task: .upload)
    func upload(url file: URL) async throws(APIError<Void>) -> ResponseMock
}

@Suite
struct FileHandlingTests {
    private static let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).bin")

    private static func okSession() -> MockSession {
        MockSession({ (request) throws(URLError) in
            (json(ResponseMock(id: "sent", value: 0)), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
    }

    private static func expectMissingFile(_ error: APIError<Void>) {
        guard case .transport(.file(.readFailed(let cocoaError))) = error else {
            Issue.record("Expected .transport(.file(.readFailed)), got \(error)")
            return
        }
        #expect(cocoaError.code == .fileReadNoSuchFile)
    }

    // MARK: - Uploads

    // URLSession sends an empty body for a missing file and the server answers 200:
    // without the check, these calls would succeed without uploading anything.

    @Test
    func aDirectUploadOfAMissingFileFailsBeforeSending() async {
        let session = Self.okSession()
        do {
            _ = try await TestAPIClient(session: session).uploadURL(url: Self.missing)
            Issue.record("Expected a failure")
        } catch {
            Self.expectMissingFile(error)
        }
        #expect(await session.recordedRequests.isEmpty)
    }

    @Test
    func aHandleUploadOfAMissingFileFailsBeforeSending() async {
        let session = Self.okSession()
        do {
            _ = try await TestAPIClient(session: session).uploadURLTask(url: Self.missing).start()
            Issue.record("Expected a failure")
        } catch {
            Self.expectMissingFile(error)
        }
        #expect(await session.recordedRequests.isEmpty)
    }

    @Test
    func aBackgroundUploadOfAMissingFileFailsBeforeCreatingTheTask() async {
        do {
            _ = try await FileUploadAPIClient().uploadBackgroundTask(url: Self.missing).start(id: UUID().uuidString)
            Issue.record("Expected a failure")
        } catch {
            Self.expectMissingFile(error)
        }
    }

    // MARK: - Downloads

    @Test
    func aDownloadIsMovedOutOfItsTemporaryFile() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("content".utf8).write(to: temporary)
        let session = MockSession()
        await session.stubDownload(responses: [(temporary, HTTPURLResponse(url: URL(string: "https://base-url.com/download")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)])

        let stored = try await TestAPIClient(session: session).download()
        defer { try? FileManager.default.removeItem(at: stored.deletingLastPathComponent()) }

        #expect(try Data(contentsOf: stored) == Data("content".utf8))
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test
    func downloadsWithTheSameNameDoNotReplaceEachOther() async throws {
        let counter = AtomicCounter()
        let session = MockSession({ (request) throws(URLError) in
            let headers = ["Content-Disposition": "attachment; filename=\"report.pdf\""]
            let n = await counter.increment()
            return (Data("download \(n)".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        })
        let api = TestAPIClient(session: session)

        let first = try await api.download()
        let second = try await api.download()
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }

        #expect(first != second)
        #expect(first.lastPathComponent == "report.pdf")
        #expect(second.lastPathComponent == "report.pdf")
        #expect(try String(contentsOf: first, encoding: .utf8) == "download 1")
        #expect(try String(contentsOf: second, encoding: .utf8) == "download 2")
    }

    @Test
    func theDelegateMovesAFinishedDownloadOutOfURLSessionsLocation() throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("finished".utf8).write(to: location)
        let store = TransferStore(root: FileManager.default.temporaryDirectory.appending(path: "beam-store-\(UUID().uuidString)"))
        defer { store.removeAll() }
        let delegate = SessionDelegate(store: store)
        let task = URLSession.shared.downloadTask(with: URL(string: "https://example.invalid/file")!)

        delegate.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: location)

        let entry = try #require(store.entries().first)
        guard case .downloaded(let kept) = store.result(of: entry).outcome else {
            Issue.record("Expected a download, got \(store.result(of: entry).outcome)")
            return
        }
        #expect(kept != location)
        #expect(!FileManager.default.fileExists(atPath: location.path))
        #expect(try Data(contentsOf: kept) == Data("finished".utf8))
    }

    // MARK: - Errors

    /// A file failure of the transport keeps its layer; its kind is `.storage`, as any file failure.
    @Test
    func fileFailuresOfTheTransportKeepTheirLayer() {
        let error = APIError<Void>(TransportError.file(.moveFailed(CocoaError(.fileWriteUnknown))))
        guard case .transport(.file(.moveFailed)) = error else {
            Issue.record("Expected .transport(.file(.moveFailed)), got \(error)")
            return
        }
        #expect(error == .storage)
    }

    @Test
    func fileURLErrorsAreStorage() {
        for code: URLError.Code in [.fileDoesNotExist, .noPermissionsToReadFile, .cannotOpenFile, .cannotWriteToFile, .cannotMoveFile] {
            #expect(APIError<Void>.transport(.network(URLError(code))) == .storage)
        }
    }

    @Test
    func fileErrorsShowThePathInTheLog() {
        let path = NSHomeDirectory() + "/Library/Caches/A/report.pdf"
        let error = FileError.readFailed(CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: path]))
        #expect(error.logDescription.contains("[~/Library/Caches/A/report.pdf]"))
    }
}

// MARK: - File operation errors

/// Each file operation fails with its own case, keeping Foundation's error.
@Suite
struct FileOperationErrorTests {
    private static let missing = URL.temporaryDirectory.appending(path: "beam-missing-\(UUID().uuidString)/file")

    @Test
    func eachOperationFailsWithItsOwnCase() {
        #expect(Self.failure { () throws(FileError) in _ = try FileUtils.read(Self.missing) }.isRead)
        #expect(Self.failure { () throws(FileError) in _ = try FileUtils.read(Self.missing, upTo: 1) }.isRead)
        #expect(Self.failure { () throws(FileError) in try FileUtils.write(Data(), to: Self.missing) }.isWrite)
        #expect(Self.failure { () throws(FileError) in try FileUtils.move(Self.missing, to: Self.missing) }.isMove)
        #expect(Self.failure { () throws(FileError) in try FileUtils.copy(Self.missing, to: Self.missing) }.isCopy)
    }

    private static func failure(_ operation: () throws(FileError) -> Void) -> FileError? {
        do throws(FileError) { try operation(); return nil } catch { return error }
    }
}

private extension Optional<FileError> {
    var isRead: Bool { if case .readFailed = self { true } else { false } }
    var isWrite: Bool { if case .writeFailed = self { true } else { false } }
    var isMove: Bool { if case .moveFailed = self { true } else { false } }
    var isCopy: Bool { if case .copyFailed = self { true } else { false } }
}

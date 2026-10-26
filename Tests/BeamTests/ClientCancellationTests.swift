//
//  ClientCancellationTests.swift
//  Beam
//
//  Verifies that a call's `cancel()` sees the in-flight task as soon as URLSession
//  reports its creation (registration used to hop through an unstructured Task).
//

import Foundation
import Synchronization
import Testing
@testable import Beam

// MARK: - Session that reports task creation like URLSession

/// Reports task creation through the task delegate, as `URLSession` does, runs
/// `afterCreation` with no suspension in between, then waits until the task is
/// cancelled. Bounded so a regression fails instead of hanging.
private final class TaskCreatingSession: SessionProtocol {
    let sessionDelegate = SessionDelegate()
    private let afterCreation: @Sendable (URLSessionTask) async -> Void

    init(afterCreation: @escaping @Sendable (URLSessionTask) async -> Void) {
        self.afterCreation = afterCreation
    }

    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) {
        let task = URLSession.shared.dataTask(with: request) // never resumed: no network
        delegate?.urlSession?(URLSession.shared, didCreateTask: task)
        await afterCreation(task)

        for _ in 0..<200 {
            if task.state == .canceling || task.state == .completed { throw URLError(.cancelled) }
            do { try await Task.sleep(for: .milliseconds(10)) } catch { throw URLError(.cancelled) }
        }
        throw URLError(.timedOut)
    }

    // Unused by these tests.
    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URLSession.AsyncBytes, URLResponse) { throw URLError(.unsupportedURL) }
    func download(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { throw URLError(.unsupportedURL) }
    func download(resumeFrom: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (URL, URLResponse) { throw URLError(.unsupportedURL) }
    func upload(for request: URLRequest, from data: Data, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { throw URLError(.unsupportedURL) }
    func upload(for: URLRequest, fromFile: URL, delegate: URLSessionTaskDelegate?) async throws(URLError) -> (Data, URLResponse) { throw URLError(.unsupportedURL) }
    func downloadTask(with request: URLRequest) -> URLSessionDownloadTask { URLSession.shared.downloadTask(with: request) }
    func downloadTask(withResumeData data: Data) -> URLSessionDownloadTask { URLSession.shared.downloadTask(withResumeData: data) }
    func uploadTask(with request: URLRequest, from data: Data) -> URLSessionUploadTask { URLSession.shared.uploadTask(with: request, from: data) }
    func uploadTask(with request: URLRequest, fromFile url: URL) -> URLSessionUploadTask { URLSession.shared.uploadTask(with: request, fromFile: url) }
    func uploadTask(withResumeData data: Data) -> URLSessionUploadTask { URLSession.shared.uploadTask(withResumeData: data) }
    func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask { URLSession.shared.webSocketTask(with: request) }
}

// MARK: - Tests

@Suite
struct ClientCancellationTests {

    @Test(arguments: 0..<20)
    func cancelRightAfterTaskCreationCancelsIt(iteration: Int) async throws {
        let created = Mutex<URLSessionTask?>(nil)
        let clientBox = Mutex<Client?>(nil)

        // Cancel in the same execution that reported the task, before any other
        // job can run: the task must already be registered at that point.
        let session = TaskCreatingSession { task in
            created.withLock { $0 = task }
            let client = clientBox.withLock { $0 }
            await client?.cancel()
        }
        let client = Client(session: session)
        clientBox.withLock { $0 = client }

        let request = URLRequest(url: URL(string: "https://example.invalid/slow")!)
        let result = await Task { () -> Result<(Data, HTTPURLResponse), TransportError> in
            do throws(TransportError) { return .success(try await client.data(for: request)) } catch { return .failure(error) }
        }.value

        let task = try #require(created.withLock { $0 })
        #expect(task.state != .suspended)
        switch result {
        case .success:
            Issue.record("Expected cancellation")
        case .failure(let error):
            #expect(error.urlError?.code == .cancelled, "Unexpected error: \(error)")
        }
    }
}

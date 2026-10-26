//
//  RelaunchAttachTests.swift
//  Beam
//
//  Attaching to a transfer left in flight by another process, as after a relaunch.
//  Two runs, in separate processes, opt-in:
//
//  BEAM_RELAUNCH=start  swift test --skip-build --filter RelaunchAttachTests
//  BEAM_RELAUNCH=attach swift test --skip-build --filter RelaunchAttachTests
//
//  The first starts a large download on a fixed background session identifier and
//  exits without awaiting it: the system keeps transferring. The second, a new
//  process, creates the session again and starts with the same id.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

private let step = ProcessInfo.processInfo.environment["BEAM_RELAUNCH"]
private let marker = FileManager.default.temporaryDirectory.appendingPathComponent("beam-relaunch-id")

/// A fixed identifier: the second process must reconnect to the first one's session.
/// Static, so the session is never released (that would cancel the transfer).
private let relaunchSession = Session(.background("com.beam.test.relaunch")) { $0.sessionSendsLaunchEvents = false }

private let request = URLRequest(url: URL(string: "https://proof.ovh.net/files/100Mb.dat")!)

private func key(_ id: String) -> BackgroundTaskKey {
    BackgroundTaskKey(id: id, method: "GET", path: "/files/100Mb.dat")
}

@Suite(.serialized, .tags(.network))
struct RelaunchAttachTests {

    @Test(.enabled(if: step == "start"))
    func startATransferAndExit() async throws {
        let id = "relaunch-\(UUID().uuidString)"
        let task = relaunchSession.makeDownloadTask(request, key: key(id))
        task.resume()
        try id.write(to: marker, atomically: true, encoding: .utf8)

        // Make sure it is transferring before the process exits.
        let deadline = ContinuousClock.now + .seconds(10)
        while task.countOfBytesReceived == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(task.countOfBytesReceived > 0)
    }

    @Test(.enabled(if: step == "attach"))
    func attachToTheTransferOfThePreviousProcess() async throws {
        let id = try String(contentsOf: marker, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: marker) }

        let created = Mutex(false)
        let transfer = try await relaunchSession.registry.transfer(key(id), pending: relaunchSession.sessionDelegate) { () throws(FileError) in
            created.withLock { $0 = true }
            return relaunchSession.makeDownloadTask(request, key: key(id))
        }

        guard case .task(let task) = transfer else {
            Issue.record("The previous process's transfer had already finished")
            return
        }
        #expect(!created.withLock { $0 }, "A new transfer was started instead of attaching")
        #expect(BackgroundTaskDescription(task.taskDescription)?.id == id)
        #expect(task.countOfBytesReceived > 0, "Attached to a task that hadn't transferred anything")

        await relaunchSession.cancelAllTasks()
    }
}

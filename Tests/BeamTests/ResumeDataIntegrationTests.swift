//
//  ResumeDataIntegrationTests.swift
//  Beam
//
//  Integration test using a real network download (Big Buck Bunny).
//  Verifies that cancelling a Client's call mid-download produces valid
//  resume data and that resuming with it works.
//
//  ⚠️ Requires internet. Run manually:
//  swift test --filter ResumeDataIntegration
//

import Foundation
import Testing
@testable import Beam

@Suite("ResumeData Integration", .tags(.network))
struct ResumeDataIntegrationTests {

    /// 100 MB file served with range support — the download won't finish before we
    /// cancel, and resuming it stays short.
    private let fileURL = URL(string: "https://proof.ovh.net/files/100Mb.dat")!

    @Test
    func downloadCancelProducesResumeData() async throws {
        let client = Client()

        // 1. Start background download
        let request = URLRequest(url: fileURL)
        let downloadTask = Task {
            try await client.download(for: request)
        }

        // 2. Wait for the download to actually start
        try await Task.sleep(for: .milliseconds(500))

        // 3. Cancel through the call's control (produces resume data)
        let resumeData = await client.cancel()

        // 4. The task should finish with an error
        do {
            _ = try await downloadTask.value
            Issue.record("Expected error after cancel")
        } catch {
            // Expected — the task was cancelled
        }

        // 5. Verify we have resume data
        #expect(resumeData != nil, "cancel() debería producir resume data")
        #expect(resumeData?.isEmpty == false, "El resume data no debería estar vacío")

        guard let validResumeData = resumeData else { return }
        print("✅ Resume data obtenido: \(validResumeData.count) bytes")

        // 6. Resume the download with the resume data
        let client2 = Client()
        let (url, response) = try await client2.download(for: request, resumeFrom: validResumeData)

        #expect(response.statusCode == 200 || response.statusCode == 206)
        let fileSize = try Data(contentsOf: url).count
        #expect(fileSize > 0, "El fichero reanudado no debería estar vacío")
        print("✅ Descarga reanudada: \(fileSize) bytes")

        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Background Session

@Suite("ResumeData Background Integration", .tags(.network))
struct ResumeDataBackgroundIntegrationTests {

    /// 100 MB file served with range support — the download won't finish before we
    /// cancel, and resuming it stays short.
    private let fileURL = URL(string: "https://proof.ovh.net/files/100Mb.dat")!

    @Test
    func downloadCancelProducesResumeDataWithBackgroundSession() async throws {
        let endpoint = Endpoint<URL, Void>(
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: "https://proof.ovh.net", path: "/files/100Mb.dat")
        )
        let handle = endpoint.backgroundDownloadTask(on: backgroundTestSession)

        // 1. Start the download on the background session
        let downloadTask = Task { () -> Result<URL, APIError<Void>> in
            do throws(APIError<Void>) { return .success(try await handle.start(id: UUID().uuidString)) } catch { return .failure(error) }
        }

        // 2. Wait for the download to actually start
        try await Task.sleep(for: .milliseconds(500))

        // 3. Cancel through the handle (produces resume data)
        let resumeData = await handle.cancel()

        // 4. The task should finish with an error
        if case .success = await downloadTask.value {
            Issue.record("Expected error after cancel")
        }

        // 5. Verify we have resume data
        #expect(resumeData != nil, "cancel() debería producir resume data")
        #expect(resumeData?.isEmpty == false, "El resume data no debería estar vacío")

        guard let validResumeData = resumeData else { return }

        // 6. Resume the download with the resume data on the background session
        let url = try await endpoint.backgroundDownloadTask(on: backgroundTestSession)
            .start(id: UUID().uuidString, resumeFrom: validResumeData)

        let fileSize = try Data(contentsOf: url).count
        #expect(fileSize > 0, "El fichero reanudado no debería estar vacío")
        try? FileManager.default.removeItem(at: url)
    }
}

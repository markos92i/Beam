//
//  ResumeDataIntegrationTests.swift
//  Beam
//
//  Integration test using a real network download (Big Buck Bunny).
//  Verifies that calling cancel() on a Client mid-download produces valid
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

    /// ~180MB file — the download won't finish before we cancel.
    private let fileURL = URL(string: "https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_480p_h264.mov")!

    @Test
    func downloadCancelProducesResumeData() async throws {
        let client = Client()

        // 1. Start background download
        let request = URLRequest(url: fileURL)
        let downloadTask = Task {
            try await client.download(for: request)
        }

        // 2. Wait for the download to actually start
        try await Task.sleep(for: .seconds(2))

        // 3. Cancel via the Client's cancel() (produces resume data)
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

    /// ~180MB file — the download won't finish before we cancel.
    private let fileURL = URL(string: "https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_480p_h264.mov")!

    @Test
    func downloadCancelProducesResumeDataWithBackgroundSession() async throws {
        let session = Session(
            identifier: "com.beam.test.resume.\(UUID().uuidString)",
            isDiscretionary: false,
            sessionSendsLaunchEvents: false
        )
        let client = Client(session: session)

        // 1. Start download via task-based path (background-compatible)
        let request = URLRequest(url: fileURL)
        let downloadTask = Task {
            try await client.downloadTask(for: request)
        }

        // 2. Wait for the download to actually start
        try await Task.sleep(for: .seconds(2))

        // 3. Cancel via the Client's cancel() (produces resume data)
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
        print("✅ Resume data obtenido (background): \(validResumeData.count) bytes")

        // 6. Resume the download with the resume data via the task-based path
        let client2 = Client(session: session)
        let (url, response) = try await client2.downloadTask(for: request, resumeFrom: validResumeData)

        #expect(response.statusCode == 200 || response.statusCode == 206)
        let fileSize = try Data(contentsOf: url).count
        #expect(fileSize > 0, "El fichero reanudado no debería estar vacío")
        print("✅ Descarga reanudada (background): \(fileSize) bytes")

        try? FileManager.default.removeItem(at: url)
    }
}

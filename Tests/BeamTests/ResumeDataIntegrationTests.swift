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

    /// Fichero ~180MB — no terminará antes de cancelar.
    private let fileURL = URL(string: "https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_480p_h264.mov")!

    @Test
    func downloadCancelProducesResumeData() async throws {
        let client = Client()

        // 1. Lanzar descarga en background
        let request = URLRequest(url: fileURL)
        let downloadTask = Task {
            try await client.download(for: request)
        }

        // 2. Esperar a que la descarga empiece realmente
        try await Task.sleep(for: .seconds(2))

        // 3. Cancelar via cancel() del Client (produce resume data)
        let resumeData = await client.cancel()

        // 4. El task debería terminar con error
        do {
            _ = try await downloadTask.value
            Issue.record("Expected error after cancel")
        } catch {
            // Esperado — la task fue cancelada
        }

        // 5. Verificar que tenemos resume data
        #expect(resumeData != nil, "cancel() debería producir resume data")
        #expect(resumeData?.isEmpty == false, "El resume data no debería estar vacío")

        guard let validResumeData = resumeData else { return }
        print("✅ Resume data obtenido: \(validResumeData.count) bytes")

        // 6. Reanudar descarga con el resume data
        let client2 = Client()
        let (url, response) = try await client2.download(for: request, resumeFrom: validResumeData)

        #expect(response.statusCode == 200 || response.statusCode == 206)
        let fileSize = try Data(contentsOf: url).count
        #expect(fileSize > 0, "El fichero reanudado no debería estar vacío")
        print("✅ Descarga reanudada: \(fileSize) bytes")

        try? FileManager.default.removeItem(at: url)
    }
}

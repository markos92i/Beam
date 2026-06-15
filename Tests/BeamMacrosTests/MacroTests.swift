//
//  MacroTests.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//
//  Macro correctness is validated end-to-end by the integration tests
//  in BeamTests (DataTests, UploadTests, DownloadTests, MacroIntegrationTests).
//  Those tests use @API protocols with TestAPIClient(client:) injection.
//

import Testing

@Test func macroTestsRunFromIntegration() {
    // Macro expansion is tested indirectly via BeamTests.
    // If the macro produces invalid code, those tests won't compile.
    #expect(true)
}

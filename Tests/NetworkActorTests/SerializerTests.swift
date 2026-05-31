//
//  SerializerTests.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 31/05/2026.
//

import Foundation
import Testing
@testable import NetworkActor

@Suite
struct SerializerTests {
    private let serializer = Serializer()
    
    @Test
    func testDictionarySerializationWithISO8601Dates() throws {
        let httpBody = HTTPBody.dictionary([
            "string_key": "SwiftConcurrency",
            "int_key": 2026,
            "bool_key": true,
            "date_key": Date(timeIntervalSince1970: 1780183200) // 2026-05-30T23:20:00Z
        ])
        
        let dataResult = try httpBody.data(with: serializer)
        
        guard let jsonObject = try JSONSerialization.jsonObject(with: dataResult, options: []) as? [String: Any] else {
            Issue.record("Not a valid JSON")
            return
        }
        
        #expect(jsonObject["string_key"] as? String == "SwiftConcurrency")
        #expect(jsonObject["int_key"] as? Int == 2026)
        #expect(jsonObject["bool_key"] as? Bool == true)
        #expect(jsonObject["date_key"] as? String == "2026-05-30T23:20:00Z")
    }
    
    @Test
    func testEmptyDictionarySerialization() throws {
        let httpBody = HTTPBody.dictionary([:])
        let dataResult = try httpBody.data(with: serializer)

        let jsonString = String(data: dataResult, encoding: .utf8)
        #expect(jsonString == "{}")
    }
}

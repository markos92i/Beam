//
//  SerializerTests.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 31/05/2026.
//

import Foundation
import Testing
@testable import Beam

@Suite
struct MapperTests {
    private let mapper = Mapper()
    
    @Test
    func json() throws {
        struct Stub: Codable, Equatable {
            var id: Int = 0
            var value: String = ""
            var date: Date = Date(timeIntervalSince1970: 1780183200) // 2026-05-30T23:20:00Z
        }
        
        let httpBody = HTTPBody.json(Stub())
        
        let dataResult = try httpBody.encode(with: mapper)
        
        guard let jsonObject: Stub = try mapper.decode(data: dataResult) else {
            Issue.record("Not a valid JSON")
            return
        }
        
        #expect(jsonObject.id == 0)
        #expect(jsonObject.value == "")
        #expect(jsonObject.date == Date(timeIntervalSince1970: 1780183200))
    }

    @Test
    func formURLEncoded() throws {
        let httpBody = HTTPBody.formURLEncoded([
            URLQueryItem(name: "username", value: "marcos"),
            URLQueryItem(name: "password", value: "s3cr3t&special=yes")
        ])

        let dataResult = try httpBody.encode(with: mapper)
        let encoded = String(data: dataResult, encoding: .utf8)!

        #expect(encoded.contains("username=marcos"))
        #expect(encoded.contains("password=s3cr3t%26special%3Dyes"))
        #expect(httpBody.contentType == .urlEncoded)
    }

    @Test
    func rawDataPreservesContentType() throws {
        let raw = "hello".data(using: .utf8)!
        let httpBody = HTTPBody.data(raw, contentType: .text())

        let dataResult = try httpBody.encode(with: mapper)
        #expect(dataResult == raw)
        #expect(httpBody.contentType == .text())
    }
}

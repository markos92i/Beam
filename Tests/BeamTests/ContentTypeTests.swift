//
//  ContentTypeTests.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 25/10/2026.
//

import Foundation
import Testing
@testable import Beam

@Suite
struct ContentTypeTests {
    /// The header is sent as written, and the common types keep their exact values.
    @Test
    func theValueIsKeptAsWritten() {
        #expect(ContentType(rawHeader: "Application/JSON;Charset=utf-8").value == "Application/JSON;Charset=utf-8")
        #expect(ContentType.json.value == "application/json; charset=UTF-8")
        #expect(ContentType.multipart(boundary: "AbC").header == ["Content-Type": "multipart/form-data; boundary=AbC"])
        #expect(ContentType(url: URL(fileURLWithPath: "/a/photo.png")) == .png)
        #expect(ContentType(url: URL(fileURLWithPath: "/a/file")) == .data)
    }

    /// Case, spacing, quotes and parameter order don't change the meaning; a boundary's case does.
    @Test
    func equalityIgnoresWhatDoesntChangeTheMeaning() {
        #expect(ContentType(rawHeader: "APPLICATION/json;charset=utf-8") == .json)
        #expect(ContentType(rawHeader: "text/plain; b=2; a=\"1\"") == "text/plain; a=1; b=2")
        #expect(ContentType.multipart(boundary: "abc") != .multipart(boundary: "ABC"))
        #expect(ContentType.json != "application/json")
        #expect(ContentType(rawHeader: "text/plain; Charset=\"UTF-8\"").parameter("charset") == "UTF-8")
    }

    /// A case matches by media type, without parameters, and a family by prefix.
    @Test
    func aSwitchCaseMatchesByMediaTypeOrFamily() {
        #expect(ContentType.json ~= "application/json")
        #expect(ContentType.image ~= .png)
        #expect(!(ContentType.image ~= "application/image"))
        #expect("*/*" ~= ContentType.pdf)
        #expect(!(ContentType.text ~= .html))
    }

    /// Error bodies and requests are reported as text when they can be read as they are.
    @Test
    func textBodiesAreRecognized() {
        for type: ContentType in [.json, "application/problem+json", "text/csv", "TEXT/XML", .urlEncoded] {
            #expect(type.isText)
        }
        for type: ContentType in [.data, .png, .pdf, .multipart(boundary: "x")] {
            #expect(!type.isText)
        }
    }

    /// The log names the type of a body by its family, or shows it as it is.
    @Test
    func theLogNamesTheContentType() {
        func logged(_ header: String) -> String {
            LogEvent.response(id: "a1", status: 200, headers: ["Content-Type": header], body: .none, start: Date())
                .rendered(bodies: false)
        }
        #expect(logged("application/json; charset=utf-8").contains("􀡅 json"))
        #expect(logged("image/x-icon").contains("􀏅 image/x-icon"))
        #expect(logged("multipart/form-data; boundary=x").contains("􀏭 multipart"))
        #expect(logged("text/xml").contains("􀙚 xml"))
        #expect(logged("application/vnd.api+json").contains("􀠩 application/vnd.api+json"))
    }
}

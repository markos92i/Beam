//
//  ElementDecoder.swift
//  Beam
//
//  How the elements of a byte stream become values.
//

import Foundation

/// Logs failures: the call already succeeded, so they never reach the monitors.
struct ElementDecoder<Element: Sendable>: Sendable {
    let decoding: BodyDecoder<Element>
    let json: JSONCoding
    let log: BeamLogger
    let id: String

    init(_ decoding: BodyDecoder<Element>, json: JSONCoding, log: BeamLogger = BeamLogger(), id: String = "") {
        self.decoding = decoding
        self.json = json
        self.log = log
        self.id = id
    }

    /// `@concurrent` so a main-actor consumer doesn't decode on the main actor.
    @concurrent
    func decode(_ text: String, what: String) async throws(APIError<Never>) -> Element {
        do {
            return try decoding.decode(Data(text.utf8), with: json)
        } catch {
            log.log(.codingFailed(id: id, what: "\(what) not decoded", detail: error.logDescription))
            throw .coding(error)
        }
    }
}

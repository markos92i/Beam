//
//  JSONLinesParser.swift
//  Beam
//
//  Parsing utility for NDJSON / JSON Lines streams.
//  Each line in the stream is a complete JSON object decoded independently.
//

import Foundation

// MARK: - ByteStream JSON Lines Extension

extension ByteStream {
    /// Decodes each non-empty line as an `Element` (NDJSON / JSON Lines).
    public func jsonLines() -> some AsyncSequence<Element, APIError<Never>> {
        LineSequence.jsonLines(lines, elements: elements)
    }
}

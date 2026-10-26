//
//  SSEParser.swift
//  Beam
//
//  Parsing utilities for Server-Sent Events (text/event-stream).
//  Applied by the caller on a ByteStream — Beam delivers the raw
//  stream, these extensions parse it.
//

import Foundation

// MARK: - SSEvent

/// A Server-Sent Event with its data undecoded.
public struct SSEvent: Sendable {
    /// `"message"` when the event has no `event:` field.
    public let event: String

    /// The `data:` lines joined by newlines.
    public let data: String

    /// The last event ID.
    public let id: String?

    /// Reconnection interval in milliseconds.
    public let retry: Int?
}

// MARK: - ByteStream SSE Extensions

extension ByteStream {
    /// Decodes each Server-Sent Event's data as an `Element`; events without data are skipped.
    public func sseEvents() -> some AsyncSequence<Element, APIError<Never>> {
        LineSequence.sseEvents(allLines, elements: elements)
    }

    /// Server-Sent Events undecoded, with their type, id and retry fields.
    public func sseRawEvents() -> some AsyncSequence<SSEvent, APIError<Never>> {
        LineSequence.sseRawEvents(allLines)
    }
}

// MARK: - SSEBuffer

struct SSEBuffer: Sendable {
    private var event: String = "message"
    private var data: [String] = []
    private var id: String?
    private var retry: Int?

    /// Returns the event a blank line completes, or `nil` while accumulating.
    mutating func feed(line: String) -> SSEvent? {
        if line.isEmpty {
            defer { reset() }
            guard !data.isEmpty else { return nil }
            return SSEvent(
                event: event,
                data: data.joined(separator: "\n"),
                id: id,
                retry: retry
            )
        }

        // SSE comment line.
        if line.hasPrefix(":") { return nil }

        let (field, value) = parseLine(line)

        switch field {
        case "event": event = value
        case "data": data.append(value)
        case "id": id = value.isEmpty ? nil : value
        case "retry":
            if let ms = Int(value) { retry = ms }
        default: break
        }

        return nil
    }

    private func parseLine(_ line: String) -> (field: String, value: String) {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return (line, "")
        }

        let field = String(line[..<colonIndex])
        var value = String(line[line.index(after: colonIndex)...])

        // The SSE spec strips only one leading space.
        if value.hasPrefix(" ") {
            value.removeFirst()
        }

        return (field, value)
    }

    private mutating func reset() {
        event = "message"
        data = []
        id = nil
        retry = nil
    }
}

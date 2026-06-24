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

/// A raw Server-Sent Event with its fields unparsed.
public struct SSEvent: Sendable {
    /// The event type (from `event:` field). Defaults to "message" if absent.
    public let event: String

    /// The data payload (from `data:` fields, joined by newlines).
    public let data: String

    /// The last event ID (from `id:` field), if present.
    public let id: String?

    /// The retry interval in milliseconds (from `retry:` field), if present.
    public let retry: Int?
}

// MARK: - ByteStream SSE Extensions

extension ByteStream {
    /// Parses the stream as Server-Sent Events and decodes each event's data
    /// payload into `Element` using the provided mapper.
    ///
    /// ```swift
    /// let stream = try await api.chat(body: request)
    /// for try await chunk in stream.sseEvents() {
    ///     self.text += chunk.delta
    /// }
    /// ```
    public func sseEvents(mapper: any MapperProtocol = Mapper()) -> SSESequence<AsyncThrowingStream<String, Error>, Element> {
        SSESequence(base: allLines, mapper: mapper)
    }

    /// Parses the stream as raw Server-Sent Events without decoding.
    ///
    /// Useful when you need access to the event type, ID, or retry fields,
    /// or when you want to handle decoding yourself.
    public func sseRawEvents() -> SSERawSequence<AsyncThrowingStream<String, Error>> {
        SSERawSequence(base: allLines)
    }
}

// MARK: - SSESequence

/// An `AsyncSequence` that parses Server-Sent Events from a line stream
/// and decodes each event's data payload into a typed value.
public struct SSESequence<Base: AsyncSequence, Element: Sendable>: AsyncSequence where Base.Element == String {

    let base: Base
    let mapper: any MapperProtocol

    public init(base: Base, mapper: any MapperProtocol = Mapper()) {
        self.base = base
        self.mapper = mapper
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator(), mapper: mapper)
    }

    public struct Iterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        let mapper: any MapperProtocol
        var buffer = SSEBuffer()

        public mutating func next() async throws -> Element? {
            while let line = try await base.next() {
                try Task.checkCancellation()
                if let event = buffer.feed(line: line), !event.data.isEmpty {
                    let data = Data(event.data.utf8)
                    return try mapper.decode(data: data)
                }
            }
            return nil
        }
    }
}

// MARK: - SSERawSequence

/// An `AsyncSequence` that parses raw Server-Sent Events without decoding the data payload.
public struct SSERawSequence<Base: AsyncSequence>: AsyncSequence where Base.Element == String {
    public typealias Element = SSEvent

    let base: Base

    public init(base: Base) {
        self.base = base
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }

    public struct Iterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        var buffer = SSEBuffer()

        public mutating func next() async throws -> SSEvent? {
            while let line = try await base.next() {
                try Task.checkCancellation()
                if let event = buffer.feed(line: line) {
                    return event
                }
            }
            return nil
        }
    }
}

// MARK: - SSEBuffer

/// Accumulates SSE lines until a blank line signals a complete event.
///
/// SSE protocol:
/// - Lines starting with `:` are comments (ignored)
/// - `event: <type>` sets the event type
/// - `data: <payload>` appends to the data buffer (multiple data lines joined by \n)
/// - `id: <value>` sets the last event ID
/// - `retry: <ms>` sets the reconnection interval
/// - A blank line dispatches the accumulated event
public struct SSEBuffer: Sendable {
    private var event: String = "message"
    private var data: [String] = []
    private var id: String?
    private var retry: Int?

    public init() {}

    /// Feeds a line to the buffer. Returns a complete `SSEvent` when a blank
    /// line terminates the current event, or `nil` if still accumulating.
    public mutating func feed(line: String) -> SSEvent? {
        // Blank line → dispatch event
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

        // Comment lines (start with `:`)
        if line.hasPrefix(":") { return nil }

        // Parse field: value
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

        // Strip single leading space from value (per SSE spec)
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

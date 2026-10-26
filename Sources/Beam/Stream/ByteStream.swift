//
//  ByteStream.swift
//  Beam
//
//  An authenticated byte stream returned by endpoints with `task: .bytes`.
//  Wraps `URLSession.AsyncBytes` after auth, interceptors, and status
//  validation have been applied. The caller decides how to consume it.
//

import Foundation

// MARK: - ByteStream

/// An authenticated HTTP byte stream whose chunks decode to `Element`.
/// Iteration fails with `APIError<Never>`: the status was validated before streaming.
public struct ByteStream<Element: Sendable>: Sendable {
    /// Throws URLSession's untyped errors; prefer ``lines`` or the decoding sequences.
    public let bytes: URLSession.AsyncBytes

    /// The HTTP response of the stream.
    public let response: HTTPURLResponse

    let elements: ElementDecoder<Element>

    private let _cancel: @Sendable () async -> Void

    /// Lines, skipping empty ones.
    public var lines: ThrowingStream<String, APIError<Never>> {
        Self.lines(of: bytes, keepingEmpty: false)
    }

    /// Lines including empty ones, which delimit SSE events.
    public var allLines: ThrowingStream<String, APIError<Never>> {
        Self.lines(of: bytes, keepingEmpty: true)
    }

    /// - Parameter json: The API's JSON settings, so elements decode like its routes.
    public init(
        bytes: URLSession.AsyncBytes,
        response: HTTPURLResponse,
        decoding: BodyDecoder<Element>,
        json: JSONCoding,
        cancel: @escaping @Sendable () async -> Void = {}
    ) {
        self.init(bytes: bytes, response: response, elements: ElementDecoder(decoding, json: json), cancel: cancel)
    }

    init(
        bytes: URLSession.AsyncBytes,
        response: HTTPURLResponse,
        elements: ElementDecoder<Element>,
        cancel: @escaping @Sendable () async -> Void
    ) {
        self.bytes = bytes
        self.response = response
        self.elements = elements
        self._cancel = cancel
    }

    /// Closes the connection; active iterations end with `.cancelled`.
    public func cancel() async {
        await _cancel()
    }

    private static func lines(of bytes: URLSession.AsyncBytes, keepingEmpty: Bool) -> ThrowingStream<String, APIError<Never>> {
        let (stream, continuation) = ThrowingStream<String, APIError<Never>>.makeStream()
        let task = Task(name: "Beam.ByteStream.lines") {
            var buffer: [UInt8] = []
            func emit() {
                if keepingEmpty || !buffer.isEmpty {
                    continuation.yield(String(decoding: buffer, as: UTF8.self))
                }
                buffer.removeAll(keepingCapacity: true)
            }
            do {
                for try await byte in bytes {
                    if byte == UInt8(ascii: "\n") {
                        emit()
                    } else if byte != UInt8(ascii: "\r") {
                        buffer.append(byte)
                    }
                }
                if !buffer.isEmpty { emit() }
                continuation.finish()
            } catch {
                continuation.finish(throwing: APIError(TransportError.network(URLError(bridging: error))))
            }
        }
        continuation.onTermination { task.cancel() }
        return stream
    }
}

// MARK: - LineSequence

struct LineSequence<Element: Sendable, State: Sendable>: AsyncSequence {
    typealias Failure = APIError<Never>

    let lines: ThrowingStream<String, Failure>
    let state: State
    /// Returns the element a line completes, or `nil` to read the next line.
    let step: @Sendable (inout State, String) async throws(Failure) -> Element?

    func makeAsyncIterator() -> Iterator {
        Iterator(lines: lines.makeAsyncIterator(), state: state, step: step)
    }

    struct Iterator: AsyncIteratorProtocol {
        var lines: ThrowingStream<String, Failure>.Iterator
        var state: State
        let step: @Sendable (inout State, String) async throws(Failure) -> Element?

        mutating func next() async throws(Failure) -> Element? {
            try await next(isolation: nil)
        }

        mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
            while let line = try await lines.next(isolation: actor) {
                if Task.isCancelled { throw .cancelled }
                if let element = try await step(&state, line) { return element }
            }
            return nil
        }
    }
}

extension LineSequence where State == Void {
    static func jsonLines(_ lines: ThrowingStream<String, Failure>, elements: ElementDecoder<Element>) -> Self {
        LineSequence(lines: lines, state: ()) { _, line throws(Failure) in
            if line.isEmpty { return nil }
            return try await elements.decode(line, what: "JSON line")
        }
    }
}

extension LineSequence where State == SSEBuffer {
    static func sseEvents(_ lines: ThrowingStream<String, Failure>, elements: ElementDecoder<Element>) -> Self {
        LineSequence(lines: lines, state: SSEBuffer()) { buffer, line throws(Failure) in
            guard let event = buffer.feed(line: line), !event.data.isEmpty else { return nil }
            return try await elements.decode(event.data, what: "SSE event")
        }
    }
}

extension LineSequence where State == SSEBuffer, Element == SSEvent {
    static func sseRawEvents(_ lines: ThrowingStream<String, Failure>) -> Self {
        LineSequence(lines: lines, state: SSEBuffer()) { buffer, line in buffer.feed(line: line) }
    }
}

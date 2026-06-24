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

/// An authenticated, typed HTTP byte stream.
///
/// The generic `Element` parameter defines what type each chunk decodes to.
/// Use `.jsonLines()` or `.sseEvents()` to iterate decoded values without
/// passing the type manually — it's inferred from the stream declaration.
///
/// ```swift
/// @Post("/chat", task: .bytes)
/// func chat(body: ChatRequest) async throws(APIError<ErrorDto>) -> ByteStream<ChatChunk>
///
/// // Caller:
/// let stream = try await api.chat(body: request)
/// for try await chunk in stream.jsonLines() {
///     self.text += chunk.delta   // chunk is ChatChunk
/// }
/// ```
public struct ByteStream<Element: Sendable>: Sendable {
    /// The raw async byte sequence from URLSession.
    public let bytes: URLSession.AsyncBytes

    /// The HTTP response associated with this stream.
    public let response: HTTPURLResponse

    /// Cancels the underlying connection. Active iterations will throw `URLError(.cancelled)`.
    private let _cancel: @Sendable () async -> Void

    /// Line-by-line access (skips empty lines — use `allLines` for SSE).
    public var lines: AsyncLineSequence<URLSession.AsyncBytes> {
        bytes.lines
    }

    /// Line-by-line access preserving empty lines. Required for SSE parsing
    /// where blank lines delimit events.
    public var allLines: AsyncThrowingStream<String, Error> {
        let bytes = self.bytes
        return AsyncThrowingStream { continuation in
            let task = Task {
                var buffer: [UInt8] = []
                do {
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(decoding: buffer, as: UTF8.self)
                            buffer.removeAll(keepingCapacity: true)
                            continuation.yield(line)
                        } else if byte != UInt8(ascii: "\r") {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(String(decoding: buffer, as: UTF8.self))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public init(bytes: URLSession.AsyncBytes, response: HTTPURLResponse, cancel: @escaping @Sendable () async -> Void = {}) {
        self.bytes = bytes
        self.response = response
        self._cancel = cancel
    }

    /// Cancels the underlying URLSession task, closing the connection.
    /// Any active `for try await` iteration will throw `URLError(.cancelled)`.
    public func cancel() async {
        await _cancel()
    }
}

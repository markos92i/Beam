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
    /// Decodes each line of the stream as an independent value of type `Element`.
    ///
    /// Blank lines are skipped. Each non-empty line is decoded using the provided mapper.
    ///
    /// ```swift
    /// let stream = try await api.feed()
    /// for try await item in stream.jsonLines() {
    ///     items.append(item)
    /// }
    /// ```
    public func jsonLines(mapper: any MapperProtocol = Mapper()) -> JSONLinesSequence<AsyncLineSequence<URLSession.AsyncBytes>, Element> {
        JSONLinesSequence(base: lines, mapper: mapper)
    }
}

// MARK: - JSONLinesSequence

/// An `AsyncSequence` that decodes each line from a base sequence as independent JSON values.
/// Blank lines are skipped. Supports cancellation checks between lines.
public struct JSONLinesSequence<Base: AsyncSequence, Element: Sendable>: AsyncSequence where Base.Element == String {

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

        public mutating func next() async throws -> Element? {
            while let line = try await base.next() {
                try Task.checkCancellation()
                guard !line.isEmpty else { continue }
                let data = Data(line.utf8)
                return try mapper.decode(data: data)
            }
            return nil
        }
    }
}

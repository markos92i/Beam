//
//  ThrowingStream.swift
//  Beam
//
//  An asynchronous stream that fails with a typed error.
//

import Foundation

/// An async stream with a typed `Failure` (`AsyncThrowingStream` only allows `any Error`).
/// Ends with `nil` when finished or cancelled; a failure is thrown once.
public struct ThrowingStream<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
    private let base: AsyncStream<Result<Element, Failure>>

    // MARK: - Producing

    struct Continuation: Sendable {
        fileprivate let base: AsyncStream<Result<Element, Failure>>.Continuation

        func yield(_ value: Element) {
            base.yield(.success(value))
        }

        func finish(throwing error: Failure? = nil) {
            if let error { base.yield(.failure(error)) }
            base.finish()
        }

        func onTermination(_ handler: @escaping @Sendable () -> Void) {
            base.onTermination = { _ in handler() }
        }
    }

    /// Unbounded buffering, so the final failure is never dropped.
    static func makeStream() -> (stream: ThrowingStream, continuation: Continuation) {
        let (stream, continuation) = AsyncStream<Result<Element, Failure>>.makeStream()
        return (ThrowingStream(base: stream), Continuation(base: continuation))
    }

    // MARK: - Consuming

    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }

    public struct Iterator: AsyncIteratorProtocol {
        private var base: AsyncStream<Result<Element, Failure>>.Iterator
        private var failed = false

        fileprivate init(base: AsyncStream<Result<Element, Failure>>.Iterator) {
            self.base = base
        }

        public mutating func next() async throws(Failure) -> Element? {
            try await next(isolation: nil)
        }

        public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
            guard !failed, let result = await base.next(isolation: actor) else { return nil }
            switch result {
            case .success(let value):
                return value
            case .failure(let error):
                failed = true
                throw error
            }
        }
    }
}

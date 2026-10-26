//
//  WebSocketHandshake.swift
//  Beam
//
//  Per-task delegate that turns the WebSocket opening handshake into an async call.
//

import Foundation
import Synchronization

/// Must be the task's delegate before `resume()`; the first callback decides the outcome.
final class WebSocketHandshake: NSObject, URLSessionWebSocketDelegate, Sendable {
    private enum State {
        case pending(CheckedContinuation<Result<Void, URLError>, Never>?)
        case finished(Result<Void, URLError>)
    }

    private let state = Mutex(State.pending(nil))

    func outcome() async -> Result<Void, URLError> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, URLError>, Never>) in
            let finished: Result<Void, URLError>? = state.withLock { state in
                switch state {
                case .pending:
                    state = .pending(continuation)
                    return nil
                case .finished(let result):
                    return result
                }
            }
            if let finished { continuation.resume(returning: finished) }
        }
    }

    private func finish(_ result: Result<Void, URLError>) {
        let waiter: CheckedContinuation<Result<Void, URLError>, Never>? = state.withLock { state in
            guard case .pending(let waiter) = state else { return nil }
            state = .finished(result)
            return waiter
        }
        waiter?.resume(returning: result)
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        finish(.success(()))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // Completing before opening means the handshake failed.
        finish(.failure(error.map { URLError(bridging: $0) } ?? URLError(.badServerResponse)))
    }
}

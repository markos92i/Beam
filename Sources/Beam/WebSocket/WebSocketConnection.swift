//
//  WebSocketConnection.swift
//  Beam
//
//  A live WebSocket connection that provides a message stream,
//  send capabilities, and disconnect control.
//

import Foundation

/// A live WebSocket connection returned by `@Socket` methods.
public struct WebSocketConnection<Success: Sendable, Failure: Sendable>: Sendable {

    /// Decoded messages across reconnections; throws the error that ended the connection.
    public let messages: ThrowingStream<Success, APIError<Failure>>

    /// Lifecycle changes; only the latest is buffered.
    public let state: AsyncStream<WebSocketConnectionState>

    let json: JSONCoding
    let log: BeamLogger
    let id: String
    let socket: Socket
    let run: Task<Void, Never>

    /// Sends raw data as a binary message.
    public func send(data: Data) async throws(APIError<Failure>) {
        do throws(WebSocketError) { try await socket.send(data: data) } catch { throw APIError(error) }
    }

    public func send(text: String) async throws(APIError<Failure>) {
        do throws(WebSocketError) { try await socket.send(text: text) } catch { throw APIError(error) }
    }

    /// Closes with `.normalClosure`.
    public func disconnect() async {
        await close(.normalClosure)
    }

    /// Socket first, so the server gets `code` rather than a cancelled receive's `.goingAway`.
    func close(_ code: URLSessionWebSocketTask.CloseCode) async {
        await socket.close(code: code)
        run.cancel()
    }
}

extension WebSocketConnection where Success: Encodable {
    /// Sends `value` as JSON in a binary message, with the API's `JSONCoding`.
    public func send(_ value: Success) async throws(APIError<Failure>) {
        try await send(data: try await Self.encode(value, json: json, log: log, id: id))
    }

    /// `@concurrent` so a main-actor caller doesn't encode on the main actor.
    @concurrent
    private static func encode(_ value: Success, json: JSONCoding, log: BeamLogger, id: String) async throws(APIError<Failure>) -> Data {
        do {
            return try json.encode(value)
        } catch {
            log.log(.codingFailed(id: id, what: "WebSocket message not encoded", detail: error.logDescription))
            throw .coding(error)
        }
    }
}

extension WebSocketConnection where Success == String {
    /// Sends `value` unencoded as a text message.
    public func send(_ value: String) async throws(APIError<Failure>) {
        try await send(text: value)
    }
}

//
//  WebSocketBehaviourTests.swift
//  Beam
//
//  WebSocket behaviour against a local server: close codes, drops, ping, sizes, frames.
//

import Foundation
import Synchronization
import Testing
@testable import Beam

struct RoomMessage: Codable, Sendable, Equatable {
    let text: String
}

/// Short retries so a test that reconnects costs little.
private let config = RequestConfig(retry: .linear(delay: .milliseconds(50), maxAttempts: 2), timeout: .seconds(2))

/// Tolerance applied over a computed worst case, for scheduling overhead and slow CI.
private let timingMargin = 3

/// Longest a correct handshake sequence can take with `config`.
private func worstCaseConnect(_ config: RequestConfig) -> Duration {
    let policy = config.retry
    let backoff = (0..<policy.maxAttempts).reduce(Duration.zero) { $0 + policy.delay(for: $1 + 1) }
    return config.timeout * (policy.maxAttempts + 1) + backoff
}

private let limit = worstCaseConnect(config) * timingMargin

private func endpoint<Message: Decodable & SendableMetatype>(_ server: LocalWebSocketServer, _ config: RequestConfig = config) -> Endpoint<Message, Void> {
    Endpoint(session: Session(), config: config, api: APIRequest(method: .get, host: server.host, path: "/"))
}

/// Polls `condition` until it holds or `limit` elapses; returns whether it held.
@discardableResult
private func eventually(within limit: Duration, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + limit
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// How a connection's `messages` ended.
private enum Ending: Sendable {
    case finished
    case failed(APIError<Void>)
    case stillOpen

    var closeCode: Int? {
        if case .failed(.connection(.closed(let code, _))) = self { code.rawValue } else { nil }
    }
    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}

private func ending<Message: Sendable>(of messages: ThrowingStream<Message, APIError<Void>>, within limit: Duration) async -> Ending {
    await withTaskGroup(of: Ending.self) { group in
        group.addTask {
            do throws(APIError<Void>) {
                for try await _ in messages {}
                return .finished
            } catch {
                return .failed(error)
            }
        }
        group.addTask {
            try? await Task.sleep(for: limit)
            return .stillOpen
        }
        let first = await group.next() ?? .stillOpen
        group.cancelAll()
        return first
    }
}

@API(host: "ws://127.0.0.1")
protocol ChatAPI {
    @Socket("/rooms/{room}")
    func join(room: String) async throws(APIError<Void>) -> WebSocketConnection<RoomMessage, RoomMessage, Void>
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct WebSocketBehaviourTests {
    // MARK: - Mocks

    /// A socket route answers with a mock connection: no server, sends recorded.
    @Test
    func aSocketRouteCanBeMocked() async throws {
        let sent = Mutex<[RoomMessage]>([])
        var api = ChatAPIClient()
        api.onJoin = { room in .mock([RoomMessage(text: "welcome to \(room)")]) { message in sent.withLock { $0.append(message) } } }
        let connection = try await api.join(room: "42")
        var messages = connection.messages.makeAsyncIterator()
        #expect(try await messages.next() == RoomMessage(text: "welcome to 42"))
        try await connection.send(RoomMessage(text: "hola"))
        #expect(sent.withLock { $0 } == [RoomMessage(text: "hola")])
        await connection.disconnect()
        #expect(try await messages.next() == nil)
    }

    // MARK: - Close codes

    @Test
    func aNormalCloseEndsWithoutError() async throws {
        let server = try await LocalWebSocketServer { connection, _ in connection.close(1000) }
        defer { server.stop() }
        let connection = try await endpoint(server).connect() as WebSocketConnection<String, String, Void>
        let ended = await ending(of: connection.messages, within: limit)
        guard case .finished = ended else { Issue.record("Ended with \(ended)"); return }
        #expect(server.connections.count == 1)
    }

    @Test(arguments: [1001, 1011])
    func aTransientCloseReconnects(code: Int) async throws {
        let server = try await LocalWebSocketServer { connection, index in
            if index == 0 { connection.close(UInt16(code)) }
        }
        defer { server.stop() }
        let connection = try await endpoint(server).connect() as WebSocketConnection<String, String, Void>
        defer { Task { await connection.disconnect() } }
        #expect(await eventually(within: limit) { server.connections.count == 2 }, "Close code \(code) didn't reconnect")
    }

    @Test(arguments: [1003, 1008, 4001])
    func aPermanentCloseEndsWithoutReconnecting(code: Int) async throws {
        let server = try await LocalWebSocketServer { connection, _ in connection.close(UInt16(code)) }
        defer { server.stop() }
        let connection = try await endpoint(server).connect() as WebSocketConnection<String, String, Void>
        defer { Task { await connection.disconnect() } }
        let ended = await ending(of: connection.messages, within: limit)
        #expect(ended.closeCode == code, "Ended with \(ended)")
        #expect(server.connections.count == 1, "Reconnected \(server.connections.count - 1) times")
    }

    /// A server that accepts and closes at once doesn't start the budget over: it gives up.
    @Test
    func aServerThatKeepsClosingGivesUp() async throws {
        let reconnect = RetryPolicy.linear(delay: .milliseconds(50), maxAttempts: 2)
        let server = try await LocalWebSocketServer { connection, _ in connection.close(1011) }
        defer { server.stop() }
        let connection: WebSocketConnection<String, String, Void> = try await endpoint(server).connect(socket: SocketConfig(reconnect: reconnect))
        let attempts = Task {
            var seen: [Int] = []
            for await case .reconnecting(let attempt, _) in connection.state { seen.append(attempt) }
            return seen
        }
        let ended = await ending(of: connection.messages, within: limit)
        #expect(ended.closeCode == 1011, "Ended with \(ended)")
        #expect(server.connections.count == reconnect.maxAttempts + 1)
        #expect(await attempts.value.allSatisfy { $0 <= reconnect.maxAttempts })
    }

    // MARK: - Drops

    /// A lost network closes the TCP connection without a close frame.
    @Test
    func aDroppedNetworkReconnects() async throws {
        let server = try await LocalWebSocketServer { connection, index in
            if index == 0 { connection.drop() }
        }
        defer { server.stop() }
        let connection = try await endpoint(server).connect() as WebSocketConnection<String, String, Void>
        defer { Task { await connection.disconnect() } }
        #expect(await eventually(within: limit) { server.connections.count == 2 })
    }

    /// A server that stops answering, without closing, is found out by the ping.
    @Test
    func aSilentServerIsDetectedByThePing() async throws {
        let ping = Duration.seconds(1)
        let server = try await LocalWebSocketServer(autoReplyPing: false)
        defer { server.stop() }
        let connection: WebSocketConnection<String, String, Void> = try await endpoint(server).connect(socket: SocketConfig(ping: ping))
        defer { Task { await connection.disconnect() } }
        #expect(await eventually(within: ping * 2 * timingMargin + limit) { server.connections.count == 2 })
    }

    // MARK: - Lifetime

    /// A connection nobody keeps, iterates or disconnects is closed.
    @Test
    func aDiscardedConnectionIsClosed() async throws {
        let server = try await LocalWebSocketServer()
        defer { server.stop() }
        do {
            _ = try await endpoint(server).connect() as WebSocketConnection<String, String, Void>
        }
        #expect(await eventually(within: limit) { server.connections.first?.isClosed == true })
    }

    /// Holding only its `messages` keeps a connection open.
    @Test
    func itsMessagesKeepAConnectionOpen() async throws {
        let server = try await LocalWebSocketServer { connection, _ in
            try? await Task.sleep(for: .milliseconds(200))
            connection.send(text: "hola")
        }
        defer { server.stop() }
        let messages = (try await endpoint(server).connect() as WebSocketConnection<String, String, Void>).messages
        var iterator = messages.makeAsyncIterator()
        #expect(try await iterator.next() == "hola")
    }

    @Test
    func sendingWhileReconnectingFailsAtOnce() async throws {
        let server = try await LocalWebSocketServer { connection, index in
            if index == 0 { connection.drop() } else { try? await Task.sleep(for: .seconds(60)) }
        }
        defer { server.stop() }
        let slow = RetryPolicy.linear(delay: .seconds(5), maxAttempts: 1)
        let connection: WebSocketConnection<String, String, Void> = try await endpoint(server).connect(socket: SocketConfig(reconnect: slow))
        defer { Task { await connection.disconnect() } }
        for await state in connection.state where state != .connected { break }
        do {
            try await connection.send(text: "lost")
            Issue.record("Expected the send to fail")
        } catch {
            guard case .connection(.notConnected) = error else { Issue.record("Got \(error)"); return }
        }
    }

    @Test
    func theChosenSubprotocolIsExposed() async throws {
        let server = try await LocalWebSocketServer(acceptsProtocol: true)
        defer { server.stop() }
        let connection: WebSocketConnection<String, String, Void> = try await endpoint(server).connect(socket: SocketConfig(protocols: ["chat.v2", "chat.v1"]))
        defer { Task { await connection.disconnect() } }
        #expect(connection.protocol == "chat.v2")
    }

    // MARK: - Messages

    /// A message beyond URLSession's limit (1 MB) ends the connection; resending it can't help.
    @Test
    func anOversizedMessageEndsTheConnection() async throws {
        let server = try await LocalWebSocketServer { connection, _ in
            connection.send(data: Data(count: 2 * 1024 * 1024))
        }
        defer { server.stop() }
        let connection = try await endpoint(server).connect() as WebSocketConnection<Data, Data, Void>
        let ended = await ending(of: connection.messages, within: limit)
        guard case .failed(.connection(.messageTooLarge)) = ended else { Issue.record("Ended with \(ended)"); return }
        #expect(server.connections.count == 1)
    }

    @Test
    func anUndecodableMessageIsSkipped() async throws {
        let server = try await LocalWebSocketServer { connection, _ in
            connection.send(text: "not json")
            connection.send(text: #"{"text":"hola"}"#)
        }
        defer { server.stop() }
        let connection = try await endpoint(server).connect() as WebSocketConnection<RoomMessage, RoomMessage, Void>
        defer { Task { await connection.disconnect() } }
        var messages = connection.messages.makeAsyncIterator()
        #expect(try await messages.next() == RoomMessage(text: "hola"))
    }

    @Test
    func jsonIsSentAsText() async throws {
        let server = try await LocalWebSocketServer()
        defer { server.stop() }
        let connection = try await endpoint(server).connect() as WebSocketConnection<RoomMessage, RoomMessage, Void>
        defer { Task { await connection.disconnect() } }
        try await connection.send(RoomMessage(text: "hola"))
        #expect(await eventually(within: limit) { !server.connections[0].frames.isEmpty })
        #expect(server.connections[0].frames.first?.isText == true)
        #expect(server.connections[0].frames.first?.text == #"{"text":"hola"}"#)
    }
}

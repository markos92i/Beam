//
//  WebSocketEchoIntegrationTests.swift
//  Beam
//
//  Integration tests using the public echo server at wss://echo.websocket.org
//  These tests verify real WebSocket connections: connect, send, receive, disconnect.
//

import Foundation
import Testing
@testable import Beam

@Suite(.serialized, .tags(.network))
struct WebSocketEchoIntegrationTests {

    private let echoHost = "wss://ws.postman-echo.com"

    // MARK: - Helpers

    /// Creates a real Endpoint configured to connect to the echo server.
    private func makeEndpoint<Message: Sendable & Codable>(
        path: String = "/raw",
        config: RequestConfig = RequestConfig(retry: .none, pingInterval: nil)
    ) -> Endpoint<Message, Void> {
        Endpoint<Message, Void>(
            config: config,
            api: APIRequest(
                method: .get,
                host: echoHost,
                path: path
            )
        )
    }

    // MARK: - Tests

    @Test
    func connectAndReceiveEcho() async throws {
        let endpoint: Endpoint<String, Void> = makeEndpoint()
        let connection = try await endpoint.connect()

        let message = "Hello Beam!"
        try await connection.send(text: message)

        var received: String?
        for try await event in connection.messages {
            if case .message(let msg) = event {
                received = msg
                break
            }
        }

        await connection.disconnect()
        #expect(received == message)
    }

    @Test
    func sendMultipleMessagesAndReceiveEchoes() async throws {
        let endpoint: Endpoint<String, Void> = makeEndpoint()
        let connection = try await endpoint.connect()

        let messages = ["uno", "dos", "tres"]
        var received: [String] = []

        for msg in messages {
            try await connection.send(text: msg)
        }

        for try await event in connection.messages {
            if case .message(let msg) = event {
                received.append(msg)
                if received.count == messages.count { break }
            }
        }

        await connection.disconnect()
        #expect(received == messages)
    }

    @Test
    func sendRapidMessagesAndReceiveAll() async throws {
        let endpoint: Endpoint<String, Void> = makeEndpoint()
        let connection = try await endpoint.connect()

        let count = 10
        for i in 0..<count {
            try await connection.send(text: "msg-\(i)")
        }

        var received: [String] = []
        for try await event in connection.messages {
            if case .message(let msg) = event {
                received.append(msg)
                if received.count == count { break }
            }
        }

        await connection.disconnect()
        #expect(received.count == count)
        for i in 0..<count {
            #expect(received[i] == "msg-\(i)")
        }
    }

    @Test
    func disconnectGracefully() async throws {
        let endpoint: Endpoint<String, Void> = makeEndpoint()
        let connection = try await endpoint.connect()

        // Verify we can connect and then disconnect cleanly
        await connection.disconnect()

        // After disconnect, the state stream should emit disconnected
        var finalState: WebSocketConnectionState?
        for await state in connection.state {
            finalState = state
            if case .disconnected = state { break }
        }

        if case .disconnected = finalState {
            // Success
        } else {
            #expect(Bool(false), "Expected disconnected state, got \(String(describing: finalState))")
        }
    }

    @Test
    func stateTransitionsOnConnect() async throws {
        let endpoint: Endpoint<String, Void> = makeEndpoint()
        let connection = try await endpoint.connect()

        // Give the connection a moment to stabilize
        try await Task.sleep(for: .milliseconds(500))

        // Send and receive to confirm it's working
        try await connection.send(text: "ping")
        for try await event in connection.messages {
            if case .message = event { break }
        }

        await connection.disconnect()

        // Collect final state
        var finalState: WebSocketConnectionState?
        for await state in connection.state {
            finalState = state
            if case .disconnected = state { break }
        }

        if case .disconnected = finalState {
            // Success
        } else {
            #expect(Bool(false), "Expected disconnected state, got \(String(describing: finalState))")
        }
    }

    @Test
    func connectionWithPingKeepAlive() async throws {
        let endpoint: Endpoint<String, Void> = makeEndpoint(
            config: RequestConfig(retry: .none, pingInterval: 2)
        )
        let connection = try await endpoint.connect()

        // Wait enough time for at least one ping cycle
        try await Task.sleep(for: .seconds(3))

        // Connection should still be alive — verify by sending a message
        try await connection.send(text: "still alive")

        var received: String?
        for try await event in connection.messages {
            if case .message(let msg) = event {
                received = msg
                break
            }
        }

        await connection.disconnect()
        #expect(received == "still alive")
    }
}

//
//  LocalWebSocketServer.swift
//  Beam
//
//  A WebSocket server on 127.0.0.1 for tests, built on Network.framework.
//

import Foundation
import Network
import Synchronization

/// A WebSocket server on 127.0.0.1. `script` runs for each connection it accepts.
final class LocalWebSocketServer: Sendable {
    typealias Script = @Sendable (_ connection: ServerConnection, _ index: Int) async -> Void

    private let listener: NWListener
    private let accepted: Accepted
    /// `ws://127.0.0.1:<port>`, for an `APIRequest` host.
    let host: String

    /// - Parameter autoReplyPing: `false` makes a server that never answers pings.
    /// - Parameter acceptsProtocol: Answers with the first subprotocol the client offers.
    init(autoReplyPing: Bool = true, acceptsProtocol: Bool = false, script: @escaping Script = { _, _ in }) async throws {
        // Network.framework delivers its callbacks on a dispatch queue.
        let queue = DispatchQueue(label: "LocalWebSocketServer")
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = autoReplyPing
        options.maximumMessageSize = 16 * 1024 * 1024
        if acceptsProtocol {
            options.setClientRequestHandler(queue) { protocols, _ in
                NWProtocolWebSocket.Response(status: .accept, subprotocol: protocols.first)
            }
        }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        let listener = try NWListener(using: parameters, on: .any)
        let accepted = Accepted()
        // Before starting, so no connection is missed.
        listener.newConnectionHandler = { connection in
            let server = ServerConnection(connection, queue: queue)
            let index = accepted.list.withLock { $0.append(server); return $0.count - 1 }
            Task { await script(server, index) }
        }

        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                let result: Result<NWEndpoint.Port, any Error>? = switch state {
                case .ready: listener.port.map { .success($0) }
                case .failed(let error): .failure(error)
                default: nil
                }
                guard let result, !resumed.withLock({ defer { $0 = true }; return $0 }) else { return }
                continuation.resume(with: result)
            }
            listener.start(queue: queue)
        }
        self.listener = listener
        self.accepted = accepted
        host = "ws://127.0.0.1:\(port.rawValue)"
    }

    var connections: [ServerConnection] { accepted.list.withLock { $0 } }

    func stop() {
        listener.cancel()
        for connection in connections { connection.drop() }
    }
}

/// Shared with the listener's handler, which can't capture a `Mutex`.
private final class Accepted: Sendable {
    let list = Mutex<[ServerConnection]>([])
}

/// One connection accepted by ``LocalWebSocketServer``.
final class ServerConnection: Sendable {
    struct Frame: Sendable {
        let isText: Bool
        let data: Data
        var text: String { String(decoding: data, as: UTF8.self) }
    }

    private let connection: NWConnection
    private let received = Mutex<[Frame]>([])
    private let ended = Mutex(false)

    fileprivate init(_ connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        connection.start(queue: queue)
        receive()
    }

    /// Text and binary frames received, in order.
    var frames: [Frame] { received.withLock { $0 } }

    /// Whether the client closed the connection or it went away.
    var isClosed: Bool { ended.withLock { $0 } }

    func send(text: String) {
        send(Data(text.utf8), opcode: .text)
    }

    func send(data: Data) {
        send(data, opcode: .binary)
    }

    /// Sends a close frame with `code`.
    func close(_ code: UInt16) {
        guard let closeCode = try? NWProtocolWebSocket.CloseCode(rawValue: code) else {
            preconditionFailure("Network.framework can't send close code \(code)")
        }
        send(Data(), opcode: .close, closeCode: closeCode)
    }

    /// Drops the TCP connection without a close frame, as a lost network does.
    func drop() {
        connection.cancel()
    }

    private func send(_ data: Data, opcode: NWProtocolWebSocket.Opcode, closeCode: NWProtocolWebSocket.CloseCode? = nil) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        if let closeCode { metadata.closeCode = closeCode }
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func receive() {
        connection.receiveMessage { [self] data, context, _, error in
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            switch metadata?.opcode {
            case .text?, .binary?:
                received.withLock { $0.append(Frame(isText: metadata?.opcode == .text, data: data ?? Data())) }
            case .close?:
                ended.withLock { $0 = true }
                return
            default:
                break
            }
            if error != nil {
                ended.withLock { $0 = true }
                return
            }
            receive()
        }
    }
}

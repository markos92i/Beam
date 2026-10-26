//
//  SocketConfig.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 26/10/2026.
//

import Foundation

/// What only a WebSocket uses: keep-alive, message size, reconnection and subprotocols.
/// The handshake still follows the route's ``RequestConfig`` (`retry`, `timeout`, auth, JSON).
public struct SocketConfig: Sendable {
    /// The frame JSON messages are sent in.
    public enum JSONFrames: Sendable {
        case text
        case binary
    }

    /// Keep-alive ping interval, between 1 and 300 seconds; `nil` sends no pings.
    public var ping: Duration?
    /// How long a pong may take before the connection counts as dropped; defaults to `ping`.
    public var pongTimeout: Duration?
    /// Largest message accepted, in bytes; a bigger one ends the connection.
    public var maxMessageSize: Int
    /// How a dropped connection is re-established.
    public var reconnect: RetryPolicy
    /// Subprotocols offered in `Sec-WebSocket-Protocol`.
    public var protocols: [String]
    public var jsonFrames: JSONFrames
    /// Application close codes (4000–4999) that reconnect; by default they end the connection.
    public var reconnectsOn: Set<Int>

    public init(
        ping: Duration? = nil,
        pongTimeout: Duration? = nil,
        maxMessageSize: Int = 1024 * 1024,
        reconnect: RetryPolicy = .resilient,
        protocols: [String] = [],
        jsonFrames: JSONFrames = .text,
        reconnectsOn: Set<Int> = []
    ) {
        self.ping = ping
        self.pongTimeout = pongTimeout
        self.maxMessageSize = maxMessageSize
        self.reconnect = reconnect
        self.protocols = protocols
        self.jsonFrames = jsonFrames
        self.reconnectsOn = reconnectsOn
    }

    /// A copy with the non-`nil` fields replaced.
    public func replacing(
        ping: Duration?? = nil,
        pongTimeout: Duration?? = nil,
        maxMessageSize: Int? = nil,
        reconnect: RetryPolicy? = nil,
        protocols: [String]? = nil,
        jsonFrames: JSONFrames? = nil,
        reconnectsOn: Set<Int>? = nil
    ) -> SocketConfig {
        SocketConfig(
            ping: ping ?? self.ping,
            pongTimeout: pongTimeout ?? self.pongTimeout,
            maxMessageSize: maxMessageSize ?? self.maxMessageSize,
            reconnect: reconnect ?? self.reconnect,
            protocols: protocols ?? self.protocols,
            jsonFrames: jsonFrames ?? self.jsonFrames,
            reconnectsOn: reconnectsOn ?? self.reconnectsOn
        )
    }

    public static let standard = SocketConfig()

    /// The ping interval URLSession can honour, or `nil`.
    var pingInterval: Duration? {
        ping.flatMap { (.seconds(1) ... .seconds(300)).contains($0) ? $0 : nil }
    }

    /// Close codes worth reconnecting after (RFC 6455 §7.4.1; IANA 1012–1014).
    func reconnects(after code: Int) -> Bool {
        [1001, 1006, 1011, 1012, 1013, 1014].contains(code) || reconnectsOn.contains(code)
    }
}

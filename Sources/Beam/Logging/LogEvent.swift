//
//  LogEvent.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 24/06/2026.
//

import Foundation

// MARK: - LogEvent

/// Unified log event describing every loggable action in Beam.
///
/// Each case carries only the data needed to render its output.
/// Formatting logic lives in computed properties, keeping call sites minimal.
enum LogEvent: Sendable {

    // MARK: - HTTP

    /// Outbound HTTP request.
    case request(rid: String, method: String, url: URL?, headers: [String: String]?, body: Data?)

    /// Inbound HTTP response.
    case response(rid: String, status: Int, headers: [String: String], body: Body, start: Date)

    /// Retry attempt before re-sending a request.
    case retry(rid: String, attempt: Int, max: Int)

    /// Non-silent API error.
    case error(rid: String, icon: String, name: String, detail: String?, attempt: Int)

    // MARK: - WebSocket

    /// WebSocket connection opened.
    case wsOpen(rid: String, url: URL?, headers: [String: String]?)

    /// Message sent over WebSocket.
    case wsSend(rid: String, type: String, size: Int)

    /// Message received over WebSocket.
    case wsReceive(rid: String, type: String, size: Int)

    /// WebSocket connection closed.
    case wsClose(rid: String, code: Int, reason: String?)

    /// Ping/pong round-trip completed.
    case wsPing(rid: String)

    /// WebSocket reconnection attempt.
    case wsReconnect(rid: String, attempt: Int, delay: TimeInterval)

    // MARK: - Auth

    /// Auth lifecycle event (refresh, state change, rejection).
    case auth(type: String, name: String, detail: String)

    // MARK: - Interceptor

    /// Request interceptor invoked.
    case interceptor(rid: String, typeName: String)
}

// MARK: - Body

extension LogEvent {
    /// Response body type for logging purposes.
    enum Body: Sendable {
        case data(Data)
        case file(URL)
        case none
    }
}

// MARK: - Metadata

extension LogEvent {

    /// Minimum log level required to emit this event.
    var level: LogLevel {
        switch self {
        case .request:          .info
        case .response(_, let status, _, _, _):
            status >= 500 ? .warning : .info
        case .retry:            .info
        case .error:            .error
        case .wsOpen:           .info
        case .wsSend:           .debug
        case .wsReceive:        .debug
        case .wsClose:          .info
        case .wsPing:           .debug
        case .wsReconnect:      .warning
        case .auth(_, _, let detail):
            detail == "rejected" ? .debug : .info
        case .interceptor:      .debug
        }
    }

    /// The os.Logger category for routing.
    var category: LogCategory {
        switch self {
        case .request, .response, .retry, .interceptor:
            .http
        case .wsOpen, .wsSend, .wsReceive, .wsClose, .wsPing, .wsReconnect:
            .websocket
        case .auth:
            .auth
        case .error:
            .error
        }
    }

    /// OSLogType used when emitting.
    var osLogType: OSLogType {
        switch self {
        case .error:                            .fault
        case .response(_, let s, _, _, _)
            where s >= 500:                     .error
        case .wsReconnect:                      .error
        case .wsSend, .wsReceive, .wsPing,
             .interceptor:                      .debug
        case .auth(_, _, let detail)
            where detail == "rejected":         .debug
        default:                                .info
        }
    }

    /// The visual block style.
    var style: LogBlock.Style {
        switch self {
        case .error: .spaced
        default:     .pipe
        }
    }
}

// MARK: - Category

extension LogEvent {
    enum LogCategory {
        case http, websocket, auth, error
    }
}

// MARK: - Rendering

extension LogEvent {

    /// Renders the event into log lines preserving the established icon scheme.
    func lines(verbose: Bool, maxBodySize: Int) -> [String] {
        switch self {

        // MARK: HTTP Request
        case .request(let rid, let method, let url, let headers, let body):
            var result = ["􀁶 \(rid)    􀋧 \(method)    \(url?.protocolLabel ?? "")    \(url?.hostLabel ?? "")    \(url?.pathAndQuery ?? "")"]
            if let headers, !headers.isEmpty {
                result.append(Self.formatHeaders(headers))
            }
            if let body, !body.isEmpty {
                if verbose {
                    result.append(contentsOf: Self.formatBodyData(body, verbose: true, max: verbose ? .max : maxBodySize))
                } else {
                    result.append("􁒡 \(body.count.byteFormatted)")
                }
            }
            return result

        // MARK: HTTP Response
        case .response(let rid, let status, let headers, let body, let start):
            let icon = switch status {
            case 200..<300: "􀁢"
            case 300..<400: "􀅴"
            default:        "􀁞"
            }
            var result = ["􀁸 \(rid)    \(icon) \(status)    􀐫 \(start.elapsed)"]
            if !headers.isEmpty { result.append(Self.formatHeaders(headers)) }
            let showBody = verbose || status >= 400
            switch body {
            case .data(let data) where !data.isEmpty:
                result.append(contentsOf: Self.formatBodyData(data, verbose: showBody, max: verbose ? .max : maxBodySize))
            case .file(let url):
                result.append("􁒡 􀈷 \(url.lastPathComponent)")
            default:
                break
            }
            return result

        // MARK: Retry
        case .retry(let rid, let attempt, let max):
            return ["􀅈 \(rid)    retry \(attempt)/\(max)"]

        // MARK: Error
        case .error(let rid, let icon, let name, let detail, let attempt):
            let context = attempt > 0 ? " attempt \(attempt)" : ""
            var result = ["􀇾 \(rid)    [\(icon) \(name)]\(context)"]
            if let detail {
                let descriptionLines = detail.split(separator: "\n", omittingEmptySubsequences: false)
                for (i, line) in descriptionLines.enumerated() {
                    result.append(i == 0 ? "􀺾 \(line)" : "  \(line)")
                }
            }
            return result

        // MARK: WS Open
        case .wsOpen(let rid, let url, let headers):
            var result = ["􀋧 \(rid)    \(url?.protocolLabel ?? "")    \(url?.hostLabel ?? "")    \(url?.pathAndQuery ?? "")"]
            if let headers, !headers.isEmpty {
                result.append(Self.formatHeaders(headers))
            }
            return result

        // MARK: WS Send
        case .wsSend(let rid, let type, let size):
            return ["􀁶 \(rid)    \(type)", "􁒡 \(size.byteFormatted)"]

        // MARK: WS Receive
        case .wsReceive(let rid, let type, let size):
            return ["􀁸 \(rid)    \(type)", "􁒡 \(size.byteFormatted)"]

        // MARK: WS Close
        case .wsClose(let rid, let code, let reason):
            let reasonStr = reason.map { "    \(String($0.prefix(120)))" } ?? ""
            return ["􀁠 \(rid)    code: \(code)\(reasonStr)"]

        // MARK: WS Ping
        case .wsPing(let rid):
            return ["􀒙 \(rid)    pong"]

        // MARK: WS Reconnect
        case .wsReconnect(let rid, let attempt, let delay):
            return ["􀅈 \(rid)    reconnect \(attempt)    delay: \(Int(delay * 1000))ms"]

        // MARK: Auth
        case .auth(let type, let name, let detail):
            return ["􁠱 \(type) [\(name)] \(detail)"]

        // MARK: Interceptor
        case .interceptor(let rid, let typeName):
            return ["􀌈 \(rid)    \(typeName)"]
        }
    }

    // MARK: - Shared Formatting

    private static func formatHeaders(_ headers: [String: String]) -> String {
        let known = headers.compactMap { key, value -> String? in
            headerLabel(key, value: value)
        }
        let others = headers.count - known.count
        let parts = known + (others > 0 ? ["+\(others)"] : [])
        return "􁒠 \(parts.joined(separator: ", "))"
    }

    private static func headerLabel(_ key: String, value: String) -> String? {
        switch key {
        case "Authorization": "􁠱 auth"
        case "Content-Type": "\(ContentType(rawHeader: value).icon) \(ContentType(rawHeader: value).label)"
        case "Cache-Control": "􀫦 cache"
        default: nil
        }
    }

    private static func formatBodyData(_ data: Data, verbose: Bool, max: Int) -> [String] {
        if verbose {
            if data.isJSON {
                return ["􁒡"] + data.jsonLog(max: max)
            } else if let text = String(data: data, encoding: .utf8) {
                return ["􁒡"] + String(text.prefix(max)).split(separator: "\n").map(String.init)
            }
        }
        return ["􁒡 \(data.count.byteFormatted)"]
    }
}

// MARK: - OSLogType (internal bridging)

import os

extension LogEvent {
    /// Bridges `OSLogType` for the `lines` rendering (avoids importing os in pure model code).
    /// This is used by `BeamLogger` to select the correct os.Logger method.
    var osLevel: OSLogType { osLogType }
}

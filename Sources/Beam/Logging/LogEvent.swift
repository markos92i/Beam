//
//  LogEvent.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 24/06/2026.
//

import Foundation

enum LogEvent: Sendable {
    // MARK: - HTTP
    case request(id: String, method: String, url: URL, headers: [String: String]?, body: Data?)
    case response(id: String, status: Int, headers: [String: String], body: Body, start: Date)
    case retry(id: String, attempt: Int, max: Int, delay: TimeInterval)
    case error(id: String, icon: String, name: String, detail: String, attempt: Int)

    // MARK: - WebSocket
    case wsOpen(id: String, url: URL, headers: [String: String]?)
    case wsSend(id: String, type: String, body: Body)
    case wsReceive(id: String, type: String, body: Body)
    case wsClose(id: String, code: Int, reason: String?)
    case wsPing(id: String)
    case wsReconnect(id: String, attempt: Int, max: Int, delay: TimeInterval)

    // MARK: - Auth
    case auth(type: String, name: String, detail: String)

    // MARK: - Interceptor
    case interceptor(id: String, typeName: String)
}

extension LogEvent {
    enum Body: Sendable {
        case data(Data)
        case file(URL)
        case none

        /// Wraps optional raw data into a `Body`.
        static func from(_ data: Data?) -> Body {
            if let data, !data.isEmpty { .data(data) } else { .none }
        }
    }
}

extension LogEvent {
    struct EventMeta: Sendable {
        let level: LogLevel
        let category: LogCategory
        let style: LogStyle
    }

    var meta: EventMeta {
        switch self {
        case .request:
            EventMeta(level: .info, category: .http, style: .pipe)
        case .response(_, let status, _, _, _):
            EventMeta(level: status >= 500 ? .warning : .info, category: .http, style: .pipe)
        case .retry:
            EventMeta(level: .info, category: .http, style: .pipe)
        case .error:
            EventMeta(level: .error, category: .error, style: .pipe)
        case .wsOpen:
            EventMeta(level: .info, category: .websocket, style: .pipe)
        case .wsSend:
            EventMeta(level: .debug, category: .websocket, style: .pipe)
        case .wsReceive:
            EventMeta(level: .debug, category: .websocket, style: .pipe)
        case .wsClose:
            EventMeta(level: .info, category: .websocket, style: .pipe)
        case .wsPing:
            EventMeta(level: .debug, category: .websocket, style: .pipe)
        case .wsReconnect:
            EventMeta(level: .warning, category: .websocket, style: .pipe)
        case .auth(_, _, let detail):
            EventMeta(level: detail == "rejected" ? .debug : .info, category: .auth, style: .pipe)
        case .interceptor:
            EventMeta(level: .debug, category: .http, style: .pipe)
        }
    }

    // MARK: - Shortcuts
    var level: LogLevel { meta.level }
    var category: LogCategory { meta.category }
    var style: LogStyle { meta.style }
}

// MARK: - Category
extension LogEvent {
    enum LogCategory {
        case http, websocket, auth, error
    }
}

// MARK: - Rendering
extension LogEvent {
    func rendered(in config: RenderConfig) -> String {
        lines(in: config).styled(meta.style).joined(separator: "\n")
    }

    @LogBuilder
    private func lines(in config: RenderConfig) -> [String] {
        switch self {
        // MARK: - HTTP
        case .request(let id, let method, let url, let headers, let body):
            "􀁶 \(id)    􀋧 \(method)    \(url.protocolLabel)    \(url.hostLabel)    \(url.pathLabel)    \(url.queryLabel ?? "")"
            "􁒠 \(Self.headerDescription(headers))"
            "􁒡 \(Self.bodyDescription(.from(body), verbose: config.verbose, max: config.maxBodySize))"
            
        case .response(let id, let status, let headers, let body, let start):
            "􀁸 \(id)    \(status.statusIcon) \(status)    􀐫 \(start.elapsed)"
            "􁒠 \(Self.headerDescription(headers))"
            "􁒡 \(Self.bodyDescription(body, verbose: config.verbose || status >= 400, max: config.verbose ? .max : config.maxBodySize))"

        case .retry(let id, let attempt, let max, let delay):
            "􀅈 \(id)    retry \(attempt)/\(max)    delay: \(delay.formatted)"

        case .error(let id, let icon, let name, let detail, let attempt):
            "􀇾 \(id)    \(icon) \(name)    attempt \(attempt)"
            "􀺾 \(detail)"

        // MARK: - WebSocket
        case .wsOpen(let id, let url, let headers):
            "􀋧 \(id)    \(url.protocolLabel)    \(url.hostLabel)    \(url.pathLabel)    \(url.queryLabel ?? "")"
            "􁒠 \(Self.headerDescription(headers))"

        case .wsSend(let id, let type, let body):
            "􀁶 \(id)    \(type)"
            "􁒡 \(Self.bodyDescription(body, verbose: config.verbose, max: config.maxBodySize))"

        case .wsReceive(let id, let type, let body):
            "􀁸 \(id)    \(type)"
            "􁒡 \(Self.bodyDescription(body, verbose: config.verbose, max: config.maxBodySize))"

        case .wsClose(let id, let code, let reason):
            "􀁠 \(id)    code: \(code)\(reason.map { "    \(String($0.prefix(config.maxBodySize)))" } ?? "")"

        case .wsPing(let id):
            "􀒙 \(id)    pong"

        case .wsReconnect(let id, let attempt, let max, let delay):
            "􀅈 \(id)    reconnect \(attempt)/\(max)    delay: \(delay.formatted)"

        // MARK: - Auth
        case .auth(let type, let name, let detail):
            "􁠱 \(type) [\(name)] \(detail)"

        // MARK: - Interceptor
        case .interceptor(let id, let typeName):
            "􀌈 \(id)    \(typeName)"
        }
    }

    // MARK: - Shared Formatting
    private static func headerDescription(_ headers: [String: String]?) -> String {
        guard let headers, !headers.isEmpty else { return "􀓔" }
        let known = headers.compactMap { key, value -> String? in
            switch key {
            case "Authorization": "􁠱 auth"
            case "Content-Type": "\(ContentType(rawHeader: value).icon) \(ContentType(rawHeader: value).label)"
            case "Cache-Control": "􀫦 cache"
            default: nil
            }
        }
        let others = headers.count - known.count
        let parts = known + (others > 0 ? ["+\(others)"] : [])
        return parts.joined(separator: ", ")
    }

    /// Returns body content as a formatted string.
    /// Starts with " " for inline (compact/file) or "\n" for multiline (verbose).
    private static func bodyDescription(_ body: Body, verbose: Bool, max: Int) -> String {
        switch body {
        case .data(let data) where !data.isEmpty:
            if verbose {
                if data.isJSON {
                    return "\n" + data.jsonLog(max: max).joined(separator: "\n")
                } else if let text = String(data: data, encoding: .utf8) {
                    return "\n" + String(text.prefix(max))
                }
            }
            return "\(data.count.byteFormatted)"
        case .file(let url):
            return "􀈷 \(url.lastPathComponent)"
        default:
            return "􀓔"
        }
    }

}



//
//  Logger.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/06/2026.
//

import Foundation

struct Logger {
    nonisolated(unsafe) public static var enabled = true
    private let maxBodySize = 300
    private let crash: (any CrashProtocol)?

    init(output: (any CrashProtocol)? = nil) {
        self.crash = output
    }

    // MARK: - Request / Response

    func request(rid: String, request: URLRequest) {
        var lines = ["􀁶 \(rid)    􀋧 \(request.httpMethod ?? "")    \(request.url?.protocolLabel ?? "")    \(request.url?.hostLabel ?? "")    \(request.url?.pathAndQuery ?? "")"]
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            lines.append(formatHeaders(headers))
        }
        if let body = request.httpBody, !body.isEmpty {
            lines.append(contentsOf: formatBody(body))
        }
        emit(lines.pipe)
    }

    func response<T>(rid: String, status: Int, headers: [String: String], value: T, start: Date) {
        let icon = status >= 400 ? "􀁞" : "􀅴"
        var parts = ["􀁸 \(rid)", "\(icon) \(status)", "􀐫 \(start.elapsed)"]
        if let info = bodyInfo(value) { parts.append(info) }
        var lines = [parts.joined(separator: "    ")]
        if !headers.isEmpty { lines.append(formatHeaders(headers)) }
        if let data = value as? Data, !data.isEmpty {
            lines.append(contentsOf: formatBody(data))
        }
        emit(lines.pipe)
    }

    // MARK: - Error

    func error(_ apiError: APIError<some Sendable>, source: Error, attempt: Int) {
        let context = attempt > 0 ? " [attempt \(attempt)]" : ""
        let (subtitle, detail): (String?, [String]) = if let info = source as? LoggableError {
            info.logLines
        } else if let fallback = apiError.detail {
            (nil, ["􀺾 \(fallback)"])
        } else {
            (nil, [])
        }
        let sub = subtitle.map { ": \($0)" } ?? ""
        var lines = ["", "􀇾 Error:    [\(apiError.icon) \(apiError.name)\(sub)\(context)]"]
        lines.append(contentsOf: detail)
        lines.append("")
        crash?.log(lines.doublePipe + "\n")
    }

    func retry(attempt: Int, maxRetries: Int) {
        emit("│ 􀅈 Retry \(attempt)/\(maxRetries) ↓")
    }

    // MARK: - WebSocket

    func webSocketOpen(rid: String, request: URLRequest) {
        var lines = ["􀀀 \(rid)    \(request.url?.protocolLabel ?? "")    \(request.url?.hostLabel ?? "")    \(request.url?.pathAndQuery ?? "")"]
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            lines.append(formatHeaders(headers))
        }
        emit(lines.pipe)
    }

    func webSocketSend(rid: String, message: URLSessionWebSocketTask.Message) {
        let (type, size) = messageInfo(message)
        emit("│ 􀁶 \(rid)    \(type)    􀐚 \(size.byteFormatted)")
    }

    func webSocketReceive(rid: String, message: URLSessionWebSocketTask.Message) {
        let (type, size) = messageInfo(message)
        emit("│ 􀁸 \(rid)    \(type)    􀐚 \(size.byteFormatted)")
    }

    func webSocketClose(rid: String, code: Int, reason: String?) {
        let reasonStr = reason.map { "    \(String($0.prefix(120)))" } ?? ""
        emit("│ 􀁠 \(rid)    code: \(code)\(reasonStr)")
    }

    func webSocketPing(rid: String) {
        emit("│ 􀋧 \(rid)")
    }

    func webSocketReconnect(rid: String, attempt: Int, delay: TimeInterval) {
        emit("│ 􀅈 \(rid)    reconnect \(attempt)    delay: \(Int(delay * 1000))ms")
    }

    // MARK: - Private

    private func emit(_ message: String) {
        guard Self.enabled else { return }
        print(message + "\n")
    }

    private func messageInfo(_ message: URLSessionWebSocketTask.Message) -> (String, Int) {
        switch message {
        case .string(let text): ("text", text.utf8.count)
        case .data(let data): ("binary", data.count)
        @unknown default: ("unknown", 0)
        }
    }

    private func formatBody(_ data: Data) -> [String] {
        if data.isJSON {
            return ["􁒡"] + data.jsonLog(max: maxBodySize)
        } else if let text = String(data: data, encoding: .utf8) {
            return ["􁒡"] + String(text.prefix(maxBodySize)).split(separator: "\n").map(String.init)
        } else {
            return ["􁒡 (\(data.count.byteFormatted))"]
        }
    }

    private func formatHeaders(_ headers: [String: String]) -> String {
        let known = headers.compactMap { key, value -> String? in
            headerLabel(key, value: value)
        }
        let others = headers.count - known.count
        let parts = known + (others > 0 ? ["+\(others)"] : [])
        return "􁒠 [\(parts.joined(separator: ", "))]"
    }

    private func headerLabel(_ key: String, value: String) -> String? {
        switch key {
        case "Authorization": return "􁠱 auth"
        case "Content-Type": return "\(ContentType(rawHeader: value).icon) \(ContentType(rawHeader: value).label)"
        case "Cache-Control": return "􀫦 cache"
        case "Content-Length": return "􀐚 \(value.byteFormatted)"
        default: return nil
        }
    }

    private func bodyInfo<T>(_ value: T) -> String? {
        switch value {
        case let data as Data where !data.isEmpty && !data.isJSON: "􀐚 \(data.count.byteFormatted)"
        case let url as URL: "􀈷 \(url.lastPathComponent)"
        default: nil
        }
    }
}

// MARK: - Private Extensions

private extension URL {
    var protocolLabel: String {
        switch scheme {
        case "https", "wss": "􀎠 \(scheme!)"
        case "http", "ws": "􀎢 \(scheme!)"
        default: scheme ?? ""
        }
    }

    var hostLabel: String {
        "􀉣 \(host() ?? "")"
    }

    var pathAndQuery: String {
        var result = "􀈕 \(path())"
        if let query { result += "?\(query)" }
        return result
    }

    var withoutScheme: String {
        absoluteString.replacingOccurrences(of: "\(scheme ?? "")://", with: "")
    }
}

private extension Data {
    var isJSON: Bool { first == 0x7B || first == 0x5B }

    func jsonLog(max: Int) -> [String] {
        let pretty = JSONHelper.prettyString(from: self) ?? String(data: self, encoding: .utf8) ?? "\(count) bytes"
        var lines = String(pretty.prefix(max)).split(separator: "\n").map(String.init)
        if pretty.count > max { lines.append("+ \(count.byteFormatted) total") }
        return lines
    }
}

private extension Int {
    var byteFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file).replacingOccurrences(of: " ", with: "")
    }
}

private extension String {
    var byteFormatted: String { (Int(self) ?? 0).byteFormatted }
}

private extension Date {
    var elapsed: String {
        let raw = Duration.seconds(-timeIntervalSinceNow).formatted(.units(allowed: [.hours, .minutes, .seconds, .milliseconds], width: .narrow, maximumUnitCount: 2, fractionalPart: .hide))
        return raw.replacingOccurrences(of: #"(\d)\s+([\w])"#, with: "$1$2", options: .regularExpression)
    }
}

private extension [String] {
    var pipe: String { map { "│ \($0)" }.joined(separator: "\n") }
    var doublePipe: String { map { "║ \($0)" }.joined(separator: "\n") }
}

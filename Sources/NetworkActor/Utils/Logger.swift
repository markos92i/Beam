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
        let secure = request.url?.scheme == "https" ? "􀎠" : "􀇂"
        let line = ["􀁶 Request: \(rid)", "􀋧 \(request.httpMethod ?? "")", "\(secure) \(request.url?.absoluteString ?? "")"]
            .joined(separator: "    ")

        var lines = [line]
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            lines.append(formatHeaders(headers))
        }
        if let body = request.httpBody, !body.isEmpty {
            lines.append("􁒡 Body:")
            lines.append(body.prettyLog(max: maxBodySize))
        }
        emit(lines.pipe)
    }

    func response<T>(rid: String, status: Int, headers: [String: String], value: T, start: Date) {
        let line: [String?] = ["􀁸 Response: \(rid)", "\(status >= 400 ? "􀁞" : "􀅴") \(status)", "􀐫 \(start.elapsed)", bodyInfo(value)]
        var lines = [line.compactMap { $0 }.joined(separator: "    ")]

        if !headers.isEmpty { lines.append(formatHeaders(headers)) }
        if let data = value as? Data, !data.isEmpty, data.isJSON {
            lines.append("􁒡 Body:")
            lines.append(contentsOf: data.jsonLog(max: maxBodySize))
        }
        emit(lines.pipe)
    }

    // MARK: - Error (via crash.log)

    func error(_ serviceError: ServiceError<some Sendable>, source: Error, attempt: Int) {
        let context = attempt > 0 ? " [attempt \(attempt)]" : ""
        var lines = ["", "􀇾 Error:    [\(serviceError.icon) \(serviceError.name)\(context)]"]

        if let detail = (source as? InfoError)?.logDetail {
            lines.append(contentsOf: detail)
        }

        lines.append("")
        crash?.log(lines.doublePipe)
    }

    func retry(attempt: Int, maxRetries: Int) {
        emit("│ ↻ Retry \(attempt)/\(maxRetries)")
    }

    // MARK: - Output

    private func emit(_ message: String) {
        #if DEBUG
        guard Self.enabled else { return }
        print(message)
        #endif
    }

    // MARK: - Headers

    private func formatHeaders(_ headers: [String: String]) -> String {
        let icons = headers
            .sorted { headerIcon($0.key) != "􀠩" && headerIcon($1.key) == "􀠩" }
            .map { headerIcon($0, value: $1) }
        return "􁒠 Header: [\(icons.joined(separator: ", "))]"
    }

    private func headerIcon(_ key: String, value: String = "") -> String {
        switch key {
        case "Authorization": "􁠱 auth"
        case "Content-Type": "\(ContentType(rawHeader: value).icon) \(ContentType(rawHeader: value).label)"
        case "Cache-Control": "􀫦 cache"
        case "Content-Length": "􀐚 \(value.byteFormatted)"
        default: "􀠩"
        }
    }

    // MARK: - Body info

    private func bodyInfo<T>(_ value: T) -> String? {
        if let data = value as? Data, !data.isEmpty, !data.isJSON { return "􀐚 \(data.count.byteFormatted)" }
        if let url = value as? URL { return "􀈷 \(url.lastPathComponent)" }
        return nil
    }
}

// MARK: - Helpers

private extension InfoError {
    var logDetail: [String]? {
        switch self {
        case let error as SerializerError:
            guard let detail = error.info["DecodingError"] ?? error.info["EncodingError"] else { return nil }
            return "\(detail)".split(separator: "\n").map(String.init)
        case let error as ClientError where error.body != nil:
            guard let body = error.body, let text = String(data: body, encoding: .utf8) else { return nil }
            return ["􀄵 \(text.prefix(200))"]
        default:
            guard let detail = info.values.first else { return nil }
            return ["􀄵 \(detail)"]
        }
    }
}

private extension Data {
    var isJSON: Bool { first == 0x7B || first == 0x5B }

    func prettyLog(max: Int) -> String {
        if isJSON { return String(truncatedPretty(max: max)) }
        return "(\(count.byteFormatted))"
    }

    func jsonLog(max: Int) -> [String] {
        var lines = truncatedPretty(max: max).split(separator: "\n").map(String.init)
        if prettyString.count > max { lines.append("+ \(count.byteFormatted) total") }
        return lines
    }

    private func truncatedPretty(max: Int) -> String {
        String(prettyString.prefix(max))
    }

    private var prettyString: String {
        JSONHelper.prettyString(from: self) ?? String(data: self, encoding: .utf8) ?? "\(count) bytes"
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

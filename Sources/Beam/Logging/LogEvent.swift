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
    case retry(id: String, attempt: Int, max: Int, delay: Duration)
    case error(id: String, icon: String, name: String, detail: String, attempt: Int)

    // MARK: - WebSocket
    case wsOpen(id: String, url: URL, headers: [String: String]?)
    case wsSend(id: String, type: String, body: Body)
    case wsReceive(id: String, type: String, body: Body)
    case wsClose(id: String, code: Int, reason: String?)
    case wsPing(id: String)
    case wsReconnect(id: String, attempt: Int, max: Int, delay: Duration)

    // MARK: - Auth
    case auth(type: String, name: String, detail: String, level: LogLevel = .info)

    case undecodedErrorBody(id: String, type: String, detail: String)
    /// Coding failure after the call succeeded (stream element, sent WebSocket message).
    case codingFailed(id: String, what: String, detail: String)

    // MARK: - Background
    /// A background transfer that finished with nobody awaiting it.
    case backgroundFinished(id: String, method: String, path: String, status: Int?, failure: String?)
}

extension LogEvent {
    enum Body: Sendable {
        case data(Data)
        case file(name: String?, bytes: Int?)
        case none

        static func from(_ data: Data?) -> Body {
            if let data, !data.isEmpty { .data(data) } else { .none }
        }
    }
}

extension LogEvent {
    struct EventMeta: Sendable {
        let level: LogLevel
        let category: LogCategory
    }

    var meta: EventMeta {
        switch self {
        case .request:      .init(level: .info, category: .http)
        case .response(_, let status, _, _, _): .init(level: status >= 500 ? .warning : .info, category: .http)
        case .retry:        .init(level: .info, category: .http)
        case .error:        .init(level: .error, category: .error)
        case .wsOpen:       .init(level: .info, category: .websocket)
        case .wsSend:       .init(level: .debug, category: .websocket)
        case .wsReceive:    .init(level: .debug, category: .websocket)
        case .wsClose:      .init(level: .info, category: .websocket)
        case .wsPing:       .init(level: .debug, category: .websocket)
        case .wsReconnect:  .init(level: .warning, category: .websocket)
        case .auth(_, _, _, let level): .init(level: level, category: .auth)
        case .undecodedErrorBody: .init(level: .warning, category: .http)
        case .codingFailed: .init(level: .error, category: .error)
        case .backgroundFinished(_, _, _, let status, let failure):
            .init(level: failure == nil && (200..<300).contains(status ?? 0) ? .info : .warning, category: .http)
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
    func rendered(bodies: Bool) -> String {
        var lines = lines(bodies: bodies)
        if !lines.isEmpty { lines[0] = LogColumns.align(lines[0]) }
        return lines.joined(separator: "\n")
    }

    @LogBuilder
    private func lines(bodies: Bool) -> [String] {
        switch self {
        // MARK: - HTTP
        case .request(let id, let method, let url, let headers, let body):
            "􀁶 \(id)\t􀋧 \(method)\t\(url.protocolLabel)\t\(url.hostLabel)\t\(url.pathLabel)\t\(url.queryLabel ?? "")"
            "􁒠 \(Self.headerDescription(headers))"
            "􁒡 \(Self.bodyDescription(.from(body), full: bodies))"
            
        case .response(let id, let status, let headers, let body, let start):
            "􀁸 \(id)\t\(status.statusIcon) \(status)\t􀐫 \(start.elapsed)"
            "􁒠 \(Self.headerDescription(headers))"
            "􁒡 \(Self.bodyDescription(body, full: bodies || status >= 400))"

        case .retry(let id, let attempt, let max, let delay):
            "􀅈 \(id)\tretry \(attempt)/\(max)\tdelay: \(delay.formatted)"

        case .error(let id, let icon, let name, let detail, let attempt):
            "􀇾 \(id)\t\(icon) \(name)\tattempt \(attempt)"
            "􀺾 \(detail)"

        case .undecodedErrorBody(let id, let type, let detail):
            "􀇿 \(id)\terror body is not \(type): the error has no body"
            "􀺾 \(detail)"

        case .codingFailed(let id, let what, let detail):
            "􀇾 \(id)\t\(what)"
            "􀺾 \(detail)"

        // MARK: - WebSocket
        case .wsOpen(let id, let url, let headers):
            "􀋧 \(id)\t\(url.protocolLabel)\t\(url.hostLabel)\t\(url.pathLabel)\t\(url.queryLabel ?? "")"
            "􁒠 \(Self.headerDescription(headers))"

        case .wsSend(let id, let type, let body):
            "􀁶 \(id)\t\(type)"
            "􁒡 \(Self.bodyDescription(body, full: bodies))"

        case .wsReceive(let id, let type, let body):
            "􀁸 \(id)\t\(type)"
            "􁒡 \(Self.bodyDescription(body, full: bodies))"

        case .wsClose(let id, let code, let reason):
            "􀁠 \(id)\tcode: \(code)\(reason.map { "\t\($0)" } ?? "")"

        case .wsPing(let id):
            "􀒙 \(id)\tpong"

        case .wsReconnect(let id, let attempt, let max, let delay):
            "􀅈 \(id)\treconnect \(attempt)/\(max)\tdelay: \(delay.formatted)"

        // MARK: - Auth
        case .auth(let type, let name, let detail, _):
            "􁠱 \(type) [\(name)] \(detail)"

        // MARK: - Background
        case .backgroundFinished(let id, let method, let path, let status, let failure):
            "􀇂 \(id)\tbackground\t􀋧 \(method)\t􀈕 \(path)"
            if let failure {
                "􀺾 \(failure)"
            } else if let status {
                "\(status.statusIcon) \(status)"
            }
        }
    }

    // MARK: - Shared Formatting
    private static func headerDescription(_ headers: [String: String]?) -> String {
        guard let headers, !headers.isEmpty else { return "􀓔" }
        let known = headers.compactMap { key, value -> String? in
            switch key {
            case "Authorization": "􁠱 auth"
            case "Content-Type": ContentType(rawHeader: value).logLabel
            case "Cache-Control": "􀫦 cache"
            default: nil
            }
        }
        let others = headers.count - known.count
        let parts = known + (others > 0 ? ["+\(others)"] : [])
        return parts.joined(separator: ", ")
    }

    private static func bodyDescription(_ body: Body, full: Bool) -> String {
        switch body {
        case .data(let data) where !data.isEmpty:
            if full, let text = data.isJSON ? data.prettyJSON : String(data: data, encoding: .utf8) {
                return "\n" + text
            }
            return "\(data.count.byteFormatted)"
        case .file(let name, let bytes):
            return ["􀈷 \(name ?? "file")", bytes?.byteFormatted].compactMap { $0 }.joined(separator: "    ")
        default:
            return "􀓔"
        }
    }

}



// MARK: - Content Type

private extension ContentType {
    var logLabel: String {
        switch self {
        case .json: "􀡅 json"
        case .image: "􀏅 \(mediaType)"
        case .video: "􀜤 \(mediaType)"
        case .audio: "􀑪 \(mediaType)"
        case "multipart/*": "􀏭 multipart"
        case .data: "􀤧 stream"
        case .text: "􀅒 text"
        case .xml, "text/xml": "􀙚 xml"
        case .html: "􀙚 html"
        case .pdf: "􀈷 pdf"
        case .urlEncoded: "􀒶 form"
        default: "􀠩 \(value)"
        }
    }
}

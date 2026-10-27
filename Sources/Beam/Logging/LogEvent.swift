//
//  LogEvent.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 24/06/2026.
//

import Foundation
import Logy

// MARK: - Subsystem and channels

extension LogSubsystem {
    /// Beam's logs (`com.beam`). `LogSubsystem.beam.level = .off` silences all of Beam.
    public static let beam = LogSubsystem("com.beam")
}

extension LogChannel {
    static let http = LogChannel(.beam, "http", signposts: .ownCategory)
    static let websocket = LogChannel(.beam, "websocket")
    static let auth = LogChannel(.beam, "auth")
    static let error = LogChannel(.beam, "error")
}

typealias BeamLogger = Logy<LogEvent>

// MARK: - Events

enum LogEvent: LogEntry {
    // MARK: - HTTP
    case request(id: String, method: String, url: URL, headers: [String: String]?, body: Data?)
    case response(id: String, status: Int, headers: [String: String], body: Body, elapsed: Duration)
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

// MARK: - Level and channel

extension LogEvent {
    var level: LogLevel {
        switch self {
        case .request, .retry, .wsOpen, .wsClose: .info
        case .response(_, let status, _, _, _): status >= 500 ? .warning : .info
        case .error, .codingFailed: .error
        case .wsSend, .wsReceive, .wsPing: .debug
        case .wsReconnect, .undecodedErrorBody: .warning
        case .auth(_, _, _, let level): level
        case .backgroundFinished(_, _, _, let status, let failure):
            failure == nil && (200..<300).contains(status ?? 0) ? .info : .warning
        }
    }

    var channel: LogChannel {
        switch self {
        case .request, .response, .retry, .undecodedErrorBody, .backgroundFinished: .http
        case .wsOpen, .wsSend, .wsReceive, .wsClose, .wsPing, .wsReconnect: .websocket
        case .auth: .auth
        case .error, .codingFailed: .error
        }
    }
}

// MARK: - Rendering

extension LogEvent {
    @LogBuilder
    func lines(bodies: Bool) -> [String] {
        switch self {
        // MARK: - HTTP
        case .request(let id, let method, let url, let headers, let body):
            "􀁶 \(id)\t􀋧 \(method)\t\(url.protocolLabel)\t\(url.hostLabel)\t\(url.pathLabel)\t\(url.queryLabel ?? "")"
            "􁒠 \(Self.headerDescription(headers))"
            "􁒡 \(Self.bodyDescription(.from(body), full: bodies))"

        // An error response always shows its body.
        case .response(let id, let status, let headers, let body, let elapsed):
            "􀁸 \(id)\t\(status.statusIcon) \(status)\t􀐫 \(elapsed.logFormatted)"
            "􁒠 \(Self.headerDescription(headers))"
            "􁒡 \(Self.bodyDescription(body, full: bodies || status >= 400))"

        case .retry(let id, let attempt, let max, let delay):
            "􀅈 \(id)\tretry \(attempt)/\(max)\tdelay: \(delay.logFormatted)"

        case .error(let id, let icon, let name, let detail, let attempt):
            "􀇾 \(id)\t\(icon) \(name)\tattempt \(attempt)"
            "􀺾 \(detail)"

        case .undecodedErrorBody(let id, let type, let detail):
            "􀇿 \(id)\terror body is not \(type): kept only in rawBody"
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
            "􀅈 \(id)\treconnect \(attempt)/\(max)\tdelay: \(delay.logFormatted)"

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
            if full, let text = data.logText {
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

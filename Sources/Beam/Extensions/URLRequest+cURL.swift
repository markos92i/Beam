//
//  URLRequest+cURL.swift
//  Beam
//

import Foundation

extension URLRequest {
    /// Generates a copy-pasteable cURL command for this request.
    ///
    /// Usage in LLDB:
    /// ```
    /// po request.curl
    /// ```
    public var curl: String {
        var parts = ["curl"]

        if let method = httpMethod, method != "GET" {
            parts.append("-X \(method)")
        }

        if let headers = allHTTPHeaderFields {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                parts.append("-H '\(key): \(value)'")
            }
        }

        if let body = httpBody, !body.isEmpty {
            if let json = String(data: body, encoding: .utf8) {
                parts.append("-d '\(json.replacingOccurrences(of: "'", with: "'\\''"))'")
            }
        }

        if let url = url?.absoluteString {
            parts.append("'\(url)'")
        }

        return parts.joined(separator: " \\\n  ")
    }
}

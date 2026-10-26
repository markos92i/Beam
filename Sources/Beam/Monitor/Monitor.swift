//
//  Monitor.swift
//  Beam
//
//  Observers of a call: logs, metrics, analytics, crash reports.
//

import Foundation

/// Observes calls without changing them; requests it receives never carry credential headers.
public protocol Monitor: Sendable {
    /// An attempt is about to be sent, after interceptors and auth.
    func didSend(_ request: URLRequest, context: EndpointContext)

    /// An attempt received a response, before interceptors and validation.
    func didReceive(_ response: Response, context: EndpointContext)

    /// The call failed and will be retried after `delay`.
    func willRetry(after error: APIError<Void>, delay: Duration, context: EndpointContext)

    /// The call succeeded.
    func didSucceed(_ response: Response, context: EndpointContext)

    /// The call failed and won't be retried.
    func didFail(_ failure: EndpointFailure, context: EndpointContext)
}

extension Monitor {
    public func didSend(_ request: URLRequest, context: EndpointContext) {}
    public func didReceive(_ response: Response, context: EndpointContext) {}
    public func willRetry(after error: APIError<Void>, delay: Duration, context: EndpointContext) {}
    public func didSucceed(_ response: Response, context: EndpointContext) {}
    public func didFail(_ failure: EndpointFailure, context: EndpointContext) {}
}

// MARK: - Credentials

extension URLRequest {
    private static func isCredential(_ name: String) -> Bool {
        let name = name.lowercased()
        return name == "authorization" || name == "proxy-authorization"
            || name == "cookie" || name.contains("token") || name.contains("secret")
    }

    var withoutCredentials: URLRequest {
        var request = self
        for name in (allHTTPHeaderFields ?? [:]).keys where Self.isCredential(name) {
            request.setValue(nil, forHTTPHeaderField: name)
        }
        return request
    }
}

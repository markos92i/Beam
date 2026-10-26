//
//  ClosureMonitor.swift
//  Beam
//

import Foundation

/// A monitor built from closures, for quick observers.
public struct ClosureMonitor: Monitor {
    private let onSend: (@Sendable (URLRequest, EndpointContext) -> Void)?
    private let onReceive: (@Sendable (Response, EndpointContext) -> Void)?
    private let onRetry: (@Sendable (APIError<Void>, Duration, EndpointContext) -> Void)?
    private let onSuccess: (@Sendable (Response, EndpointContext) -> Void)?
    private let onFailure: (@Sendable (EndpointFailure, EndpointContext) -> Void)?

    public init(
        didSend: (@Sendable (URLRequest, EndpointContext) -> Void)? = nil,
        didReceive: (@Sendable (Response, EndpointContext) -> Void)? = nil,
        willRetry: (@Sendable (APIError<Void>, Duration, EndpointContext) -> Void)? = nil,
        didSucceed: (@Sendable (Response, EndpointContext) -> Void)? = nil,
        didFail: (@Sendable (EndpointFailure, EndpointContext) -> Void)? = nil
    ) {
        self.onSend = didSend
        self.onReceive = didReceive
        self.onRetry = willRetry
        self.onSuccess = didSucceed
        self.onFailure = didFail
    }

    public func didSend(_ request: URLRequest, context: EndpointContext) { onSend?(request, context) }
    public func didReceive(_ response: Response, context: EndpointContext) { onReceive?(response, context) }
    public func willRetry(after error: APIError<Void>, delay: Duration, context: EndpointContext) { onRetry?(error, delay, context) }
    public func didSucceed(_ response: Response, context: EndpointContext) { onSuccess?(response, context) }
    public func didFail(_ failure: EndpointFailure, context: EndpointContext) { onFailure?(failure, context) }
}

//
//  RequestConfig.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 14/05/2026.
//

import Foundation

public struct RequestConfig: Sendable, Equatable {
    public var retry: RetryPolicy
    public var timeout: TimeInterval
    public var pingInterval: TimeInterval?
    public var authPolicy: AuthPolicy

    public init(
        retry: RetryPolicy = .standard,
        timeout: TimeInterval = 30,
        pingInterval: TimeInterval? = nil,
        authPolicy: AuthPolicy = .required
    ) {
        self.retry = retry
        self.timeout = timeout
        self.pingInterval = pingInterval
        self.authPolicy = authPolicy
    }

    /// Returns a copy with only the specified fields replaced.
    /// Fields passed as `nil` keep their current value.
    public func replacing(
        retry: RetryPolicy? = nil,
        timeout: TimeInterval? = nil,
        pingInterval: TimeInterval?? = nil,
        authPolicy: AuthPolicy? = nil
    ) -> RequestConfig {
        RequestConfig(
            retry: retry ?? self.retry,
            timeout: timeout ?? self.timeout,
            pingInterval: pingInterval ?? self.pingInterval,
            authPolicy: authPolicy ?? self.authPolicy
        )
    }

    public static let standard = RequestConfig()
}

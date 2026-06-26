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

    public init(
        retry: RetryPolicy = .standard,
        timeout: TimeInterval = 60,
        pingInterval: TimeInterval? = nil
    ) {
        self.retry = retry
        self.timeout = timeout
        self.pingInterval = pingInterval
    }

    public static let standard = RequestConfig()
}

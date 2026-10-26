//
//  RequestConfig.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 14/05/2026.
//

import Foundation

// Not `Equatable`: the JSON strategies can be closures (`.custom`), which don't compare.
public struct RequestConfig: Sendable {
    public var retry: RetryPolicy
    public var timeout: Duration
    public var authPolicy: AuthPolicy
    /// How JSON bodies are encoded and decoded.
    public var json: JSONCoding

    public init(
        retry: RetryPolicy = .standard,
        timeout: Duration = .seconds(30),
        authPolicy: AuthPolicy = .required,
        json: JSONCoding = .default
    ) {
        self.retry = retry
        self.timeout = timeout
        self.authPolicy = authPolicy
        self.json = json
    }

    /// A copy with the non-`nil` fields replaced.
    public func replacing(
        retry: RetryPolicy? = nil,
        timeout: Duration? = nil,
        authPolicy: AuthPolicy? = nil,
        json: JSONCoding? = nil
    ) -> RequestConfig {
        RequestConfig(
            retry: retry ?? self.retry,
            timeout: timeout ?? self.timeout,
            authPolicy: authPolicy ?? self.authPolicy,
            json: json ?? self.json
        )
    }

    public static let standard = RequestConfig()
}

// MARK: - Foundation Bridging

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

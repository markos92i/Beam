//
//  TransportTrustPolicy.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 3/7/26.
//

import Foundation

/// Policy for evaluating server trust challenges (SSL pinning, certificate validation, etc.).
///
/// Implement this protocol in your app to provide custom trust evaluation
/// that applies to all requests made through a ``Session``.
///
/// ```swift
/// struct AppTrustPolicy: TransportTrustPolicy {
///     func evaluate(challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
///         // Custom SSL pinning logic
///     }
/// }
/// ```
public protocol TransportTrustPolicy: Sendable {
    /// Evaluates a server trust authentication challenge.
    ///
    /// - Parameter challenge: The authentication challenge from the server.
    /// - Returns: A tuple with the disposition and optional credential.
    func evaluate(challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?)
}

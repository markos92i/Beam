//
//  TransportTrustPolicy.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 3/7/26.
//

import Foundation

/// Server trust evaluation (SSL pinning, certificate validation) for every request of a ``Session``.
public protocol TransportTrustPolicy: Sendable {
    /// Evaluates a server trust authentication challenge.
    func evaluate(challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?)
}

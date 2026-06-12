//
//  NetworkDelegate.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 19/9/24.
//

import Foundation

final class NetworkDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let certificates: [Data]
    private let onTaskCreated: (@Sendable (URLSessionTask) -> Void)?

    init(
        certificates: [Data],
        onTaskCreated: (@Sendable (URLSessionTask) -> Void)? = nil
    ) {
        self.certificates = certificates
        self.onTaskCreated = onTaskCreated
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trust = challenge.protectionSpace.serverTrust, SecTrustGetCertificateCount(trust) > 0 else {
            return (.cancelAuthenticationChallenge, nil)
        }

        guard let certificate = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return (.cancelAuthenticationChallenge, nil)
        }

        let data: NSData = SecCertificateCopyData(certificate[0])
        guard certificates.isEmpty || certificates.contains(where: { data.isEqual(to: $0) }) else {
            return (.cancelAuthenticationChallenge, nil)
        }

        return (.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        onTaskCreated?(task)
    }
}

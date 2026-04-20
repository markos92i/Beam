//
//  NetworkDelegate.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation

final class NetworkDelegate: NSObject, URLSessionTaskDelegate {
    private let certificates: [Data]
    private let continuation: AsyncStream<Progress>.Continuation

    init(certificates: [Data], continuation: AsyncStream<Progress>.Continuation) {
        self.certificates = certificates
        self.continuation = continuation
    }

    // MARK: - URLSessionTaskDelegate
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        Task {
            await NetworkActor.queue.append(session)
            continuation.yield(task.progress)
        }
    }
    
    // MARK: - URLAuthenticationChallenge
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
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
}

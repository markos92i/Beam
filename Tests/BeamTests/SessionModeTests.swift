//
//  SessionModeTests.swift
//  Beam
//
//  `Session(_ mode:trustPolicy:configure:)`: the mode decides the kind, and the
//  configuration is the app's. Misusing a kind (a background session as
//  `@API(session:)`, a foreground one as `background:`, `finished` on a foreground
//  session) doesn't compile, so it can't be tested here.
//

import Foundation
import Testing
@testable import Beam

private let backgroundSession = Session(.background("com.beam.test.mode.\(UUID().uuidString)")) {
    $0.allowsCellularAccess = false
    $0.sessionSendsLaunchEvents = false
}

// Background sessions stay alive for the process: releasing one while other suites
// transfer in the background disturbs them.
private let rejectingBackground = Session(.background("com.beam.test.mode.trust.\(UUID().uuidString)"), trustPolicy: RejectingTrust()) {
    $0.sessionSendsLaunchEvents = false
}

@Suite
struct SessionModeTests {

    @Test
    func theModeDecidesTheKind() {
        let plain = Session()
        let ephemeral = Session(.ephemeral)
        #expect(type(of: plain) == Session<Foreground>.self)
        #expect(type(of: ephemeral) == Session<Foreground>.self)
        #expect(type(of: backgroundSession) == Session<Background>.self)
    }

    @Test
    func eachModeStartsFromItsConfiguration() {
        #expect(Session().urlSession.configuration.identifier == nil)
        #expect(Session(.ephemeral).urlSession.configuration.urlCache?.diskCapacity == 0)
        #expect(backgroundSession.identifier.hasPrefix("com.beam.test.mode."))
    }

    @Test
    func configureAdjustsTheRealConfiguration() {
        let session = Session(.ephemeral) {
            $0.waitsForConnectivity = true
            $0.httpMaximumConnectionsPerHost = 3
        }
        #expect(session.urlSession.configuration.waitsForConnectivity)
        #expect(session.urlSession.configuration.httpMaximumConnectionsPerHost == 3)
        #expect(!backgroundSession.urlSession.configuration.allowsCellularAccess)
    }

    @Test
    func theTrustPolicyIsUsedByBothKinds() async {
        let foreground = Session(.ephemeral, trustPolicy: RejectingTrust())
        for delegate in [foreground.sessionDelegate, rejectingBackground.sessionDelegate] {
            let task = URLSession(configuration: .ephemeral).dataTask(with: URL(string: "https://base-url.com")!)
            let (disposition, _) = await delegate.urlSession(URLSession.shared, task: task, didReceive: Self.serverTrustChallenge())
            #expect(disposition == .cancelAuthenticationChallenge)
        }
    }

    private static func serverTrustChallenge() -> URLAuthenticationChallenge {
        final class Sender: NSObject, URLAuthenticationChallengeSender {
            func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
            func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
            func cancel(_ challenge: URLAuthenticationChallenge) {}
        }
        let space = URLProtectionSpace(
            host: "base-url.com", port: 443, protocol: "https",
            realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        return URLAuthenticationChallenge(
            protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
            failureResponse: nil, error: nil, sender: Sender()
        )
    }
}

private struct RejectingTrust: TransportTrustPolicy {
    func evaluate(challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.cancelAuthenticationChallenge, nil)
    }
}

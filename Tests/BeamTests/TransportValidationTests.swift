//
//  TransportValidationTests.swift
//  Beam
//
//  `Client` returns every response whatever its status; `Endpoint` validates it and
//  decodes the error body — including for downloads and byte streams, whose body
//  used to be lost. Also covers trust-policy rejections reported as `.cancelled`.
//

import Foundation
import Testing
@testable import Beam

private struct ErrorBody: Codable, Equatable, Sendable {
    let code: String
}

private func responding(_ status: Int, body: Data) -> MockSession {
    MockSession({ (request) throws(URLError) in
        (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    })
}

private let errorBody = json(ErrorBody(code: "E42"))
private let api = APIRequest(method: .get, host: "https://base-url.com", path: "/x")

struct TransportValidationTests {

    @Test
    func clientReturnsNon2xxResponsesWithoutThrowing() async throws {
        let client = Client(session: responding(404, body: errorBody))
        let (data, response) = try await client.data(for: URLRequest(url: URL(string: "https://base-url.com/x")!))
        #expect(response.statusCode == 404)
        #expect(data == errorBody)
    }

    @Test
    func dataErrorBodyIsDecoded() async {
        let endpoint = Endpoint<ResponseMock, ErrorBody>(session: responding(409, body: errorBody), config: .init(retry: .none), api: api)
        do {
            _ = try await endpoint.data()
            Issue.record("Should have thrown")
        } catch {
            #expect(error == .http(status: .conflict))
            #expect(error.body == ErrorBody(code: "E42"))
        }
    }

    @Test
    func downloadErrorBodyIsReadFromTheDownloadedFile() async {
        let endpoint = Endpoint<URL, ErrorBody>(session: responding(403, body: errorBody), config: .init(retry: .none), api: api)
        do {
            _ = try await endpoint.download()
            Issue.record("Should have thrown")
        } catch {
            #expect(error == .http(status: .forbidden))
            #expect(error.body == ErrorBody(code: "E42"))
        }
    }

    @Test
    func streamErrorBodyIsReadFromTheStream() async {
        let endpoint = Endpoint<ResponseMock, ErrorBody>(session: responding(422, body: errorBody), config: .init(retry: .none), api: api)
        do {
            _ = try await endpoint.stream()
            Issue.record("Should have thrown")
        } catch {
            #expect(error == .http(status: .unprocessableEntity))
            #expect(error.body == ErrorBody(code: "E42"))
        }
    }

    // MARK: - Trust policy rejections

    @Test
    func aTrustRejectionTurnsCancelledIntoACertificateError() async {
        let delegate = SessionDelegate(trustPolicy: RejectingPolicy())
        let task = URLSession(configuration: .ephemeral).dataTask(with: URL(string: "https://base-url.com")!)

        // URLSession asks the policy, which rejects the server…
        _ = await delegate.urlSession(URLSession.shared, task: task, didReceive: ServerTrustChallenge.make())

        // …and then reports the task as cancelled.
        let resolved = delegate.resolve(URLError(.cancelled), for: task)
        #expect(resolved.code == .serverCertificateUntrusted)
        #expect(APIError<Void>(TransportError.network(resolved)) == .sslError)

        // The mark is consumed: a later cancellation of the same task is a real one.
        #expect(delegate.resolve(URLError(.cancelled), for: task).code == .cancelled)
    }

    /// End to end against a real server: URLSession delivers the trust challenge to
    /// the task-level method and reports the rejection as `.cancelled`; Beam must
    /// surface it as an SSL error, not as a cancellation.
    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func aPinningRejectionIsAnSSLErrorEndToEnd() async {
        let session = Session(.ephemeral, trustPolicy: RejectingPolicy())
        let endpoint = Endpoint<ResponseMock, Void>(
            session: session,
            config: .init(retry: .none),
            api: APIRequest(method: .get, host: "https://www.apple.com", path: "/")
        )
        do {
            _ = try await endpoint.data()
            Issue.record("Should have thrown")
        } catch {
            #expect(error == .sslError, "Got \(error)")
            #expect(!error.isExpected)
        }
    }

    @Test
    func aCancellationWithoutRejectionStaysCancelled() {
        let delegate = SessionDelegate(trustPolicy: RejectingPolicy())
        let task = URLSession(configuration: .ephemeral).dataTask(with: URL(string: "https://base-url.com")!)
        #expect(delegate.resolve(URLError(.cancelled), for: task).code == .cancelled)
    }

}

// MARK: - Fixtures

private struct RejectingPolicy: TransportTrustPolicy {
    func evaluate(challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.cancelAuthenticationChallenge, nil)
    }
}

/// A server-trust challenge, as URLSession sends during the TLS handshake.
private enum ServerTrustChallenge {
    final class Sender: NSObject, URLAuthenticationChallengeSender {
        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
        func cancel(_ challenge: URLAuthenticationChallenge) {}
    }

    static func make() -> URLAuthenticationChallenge {
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

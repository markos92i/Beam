//
//  ErrorModelTests.swift
//  Beam
//
//  The layered error model: each layer's error is kept intact inside `APIError`,
//  `Kind` gives the flat vocabulary, and names/ids stay stable for crash grouping.
//

import Foundation
import Testing
@testable import Beam

struct ErrorModelTests {

    private func transport(_ code: URLError.Code) -> APIError<Void> {
        APIError(TransportError.network(URLError(code)))
    }

    // MARK: - URLError classification

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, "noConnection"),
        (.networkConnectionLost, "noConnection"),
        (.dataNotAllowed, "noConnection"),
        (.timedOut, "timedOut"),
        (.cannotFindHost, "serverUnreachable"),
        (.dnsLookupFailed, "serverUnreachable"),
        (.cannotConnectToHost, "serverUnreachable"),
        (.secureConnectionFailed, "sslError"),
        (.serverCertificateUntrusted, "sslError"),
        (.badServerResponse, "noResponse"),
        (.cancelled, "cancelled"),
        (.badURL, "unknown"),
    ])
    func urlErrorsAreClassifiedByCode(code: URLError.Code, kind: String) {
        #expect(transport(code).name == kind)
    }

    @Test
    func theURLErrorIsKept() {
        guard case .transport(.network(let urlError)) = transport(.timedOut) else {
            Issue.record("Unexpected error")
            return
        }
        #expect(urlError.code == .timedOut)
    }

    @Test
    func transientFailuresMatchTheRetryableSet() {
        #expect(URLError(.timedOut).isTransient)
        #expect(URLError(.networkConnectionLost).isTransient)
        #expect(URLError(.notConnectedToInternet).isTransient)
        #expect(!URLError(.dataNotAllowed).isTransient)
        #expect(!URLError(.cannotFindHost).isTransient)
    }

    @Test
    func bridgingKeepsURLErrorsAndMapsCancellation() {
        #expect(URLError(bridging: URLError(.timedOut)).code == .timedOut)
        #expect(URLError(bridging: CancellationError()).code == .cancelled)
        struct Custom: Error {}
        #expect(URLError(bridging: Custom()).code == .unknown)
    }

    // MARK: - Cancellation

    @Test
    func everyCancellationBecomesCancelled() {
        let errors: [APIError<Void>] = [
            APIError(TransportError.network(URLError(.cancelled))),
            APIError(AuthError.cancelled),
            APIError(WebSocketError.network(URLError(.cancelled))),
        ]
        for error in errors {
            guard case .cancelled = error else {
                Issue.record("\(error) is not .cancelled")
                continue
            }
        }
    }

    // MARK: - Layers kept intact

    @Test
    func decodingErrorsReachTheCaller() {
        struct Dto: Decodable { let id: Int }
        let thrown: CodingError
        do {
            let _: Dto = try JSONCoding.default.decode(Dto.self, from: Data(#"{"id":"x"}"#.utf8))
            Issue.record("Should have thrown")
            return
        } catch {
            thrown = error
        }

        let error: APIError<Void> = .coding(thrown)
        guard case .coding(.decoding(_, let description)) = error else {
            Issue.record("Unexpected \(error)")
            return
        }
        #expect(description.contains("id"))
        #expect(error == .decode)
    }

    @Test
    func customEncodingErrorsAreKeptAsUnderlying() {
        struct Failing: Encodable {
            struct Custom: Error {}
            func encode(to encoder: any Encoder) throws { throw Custom() }
        }
        do {
            _ = try JSONCoding.default.encode(Failing())
            Issue.record("Should have thrown")
        } catch {
            guard case .encoding(.invalidValue(_, let context), _) = error else {
                Issue.record("Unexpected \(error)")
                return
            }
            #expect(context.underlyingError is Failing.Custom)
        }
    }

    @Test
    func downloadFileFailuresAreStorage() {
        let error: APIError<Void> = APIError(TransportError.file(.writeFailed(CocoaError(.fileWriteUnknown))))
        #expect(error == .storage)
    }

    @Test
    func aCancelledWebSocketSendIsCancelled() {
        #expect(APIError<Void>(WebSocketError.sendFailed(URLError(.cancelled))) == .cancelled)
        #expect(APIError<Void>(WebSocketError.sendFailed(URLError(.networkConnectionLost))) == .sendFailed)
    }

    @Test
    func invalidCredentialsNoLongerPretendsToBeA401() {
        let error = APIError<Void>(AuthError.invalidCredentials)
        #expect(error == .invalidCredentials)
        #expect(error.status == nil)
        #expect(error.id == 16)
    }

    // MARK: - Kind comparisons

    @Test
    func kindComparisonsReadLikeCaseComparisons() {
        let error = transport(.timedOut)
        #expect(error == .timedOut)
        #expect(error != .cancelled)
        #expect(APIError<Void>.http(status: .notFound) == .http(status: .notFound))
        #expect(APIError<Void>.http(status: .notFound) != .http(status: .badRequest))
    }

    @Test
    func expectedErrorsAreTheOnesNotWorthReporting() {
        #expect(APIError<Void>.cancelled.isExpected)
        #expect(transport(.notConnectedToInternet).isExpected)
        #expect(transport(.timedOut).isExpected)
        #expect(!transport(.serverCertificateUntrusted).isExpected)
        #expect(!APIError<Void>.http(status: .internalServerError).isExpected)
        #expect(!APIError<Void>(AuthError.missingToken).isExpected)
    }

    // MARK: - Stable names and ids (crash report grouping)

    @Test
    func legacyNamesAndIdsAreUnchanged() {
        let cases: [(APIError<Void>, String, Int)] = [
            (.coding(.typeMismatch), "typeMismatch", 3),
            (.invalidURL, "invalidURL", 10),
            (.auth(.missingToken), "missingToken", 13),
            (.auth(.failedToRefreshToken), "tokenExpired", 14),
            (.missingValue("userID"), "missingValue(userID)", 15),
            (transport(.notConnectedToInternet), "noConnection", 20),
            (transport(.timedOut), "timedOut", 21),
            (transport(.badServerResponse), "noResponse", 24),
            (.connection(.closed(code: .abnormalClosure, reason: nil)), "connectionClosed", 25),
            (.http(status: .notFound), "http(404)", 404),
            (.storage(.writeFailed(CocoaError(.fileWriteUnknown))), "storage", 90),
            (.cancelled, "cancelled", 91),
        ]
        for (error, name, id) in cases {
            #expect(error.name == name)
            #expect(error.id == id)
        }
    }

    @Test
    func sendFailuresHaveTheirOwnKind() {
        let error: APIError<Void> = .connection(.sendFailed(URLError(.networkConnectionLost)))
        #expect(error == .sendFailed)
        #expect(error.id == 26)
        #expect(!error.isRetryable(for: .get))
    }
}

// MARK: - HTTPStatus

@Suite
struct HTTPStatusTests {
    @Test(arguments: [103, 425, 509, 520, 521, 522, 523, 524, 525, 526, 527, 530])
    func addedCodesAreKnown(_ code: Int) throws {
        let status = try #require(HTTPStatus(rawValue: code))
        #expect(status.name != HTTPStatus.undefined.name)
        #expect(status.description == "\(code) \(status.name)")
    }

    /// Cloudflare's "the origin didn't answer" codes are retried like a 502/504. As `.undefined` they weren't.
    @Test(arguments: [HTTPStatus.webServerReturnedUnknownError, .webServerIsDown, .connectionTimedOut, .originIsUnreachable, .timeoutOccurred])
    func cloudflareGatewayCodesAreRetried(_ status: HTTPStatus) {
        let error: APIError<Void> = .http(status: status)
        #expect(status.type == .serverError)
        #expect(error.isRetryable(for: .get))
    }

    /// Server errors that repeat the same answer: not implemented, protocol or SSL configuration.
    @Test(arguments: [HTTPStatus.notImplemented, .HTTPVersionNotSupported, .networkAuthenticationRequired,
                      .SSLHandshakeFailed, .invalidSSLCertificate, .railgunError, .originDNSError])
    func permanentServerErrorsAreNotRetried(_ status: HTTPStatus) {
        let error: APIError<Void> = .http(status: status)
        #expect(status.type == .serverError)
        #expect(!error.isRetryable(for: .get))
    }

    @Test
    func requestTimeoutIsTheOnlyRetriedClientError() {
        #expect(APIError<Void>.http(status: .requestTimeout).isRetryable(for: .get))
        #expect(!APIError<Void>.http(status: .tooEarly).isRetryable(for: .get))
        #expect(!APIError<Void>.http(status: .tooManyRequests).isRetryable(for: .get))
    }
}

// MARK: - Retries by method

/// RFC 9110 §9.2.2: what the server may have applied is repeated only for idempotent methods.
@Suite
struct RetryClassificationTests {
    static let idempotent: [HTTPMethod] = [.get, .head, .options, .trace, .put, .delete]
    static let nonIdempotent: [HTTPMethod] = [.post, .patch]

    static let mayHaveBeenApplied: [APIError<Void>] = [
        .http(status: .internalServerError), .http(status: .serviceUnavailable), .http(status: .requestTimeout),
        .transport(.network(URLError(.timedOut))), .transport(.network(URLError(.networkConnectionLost)))
    ]

    @Test(arguments: idempotent, mayHaveBeenApplied)
    func idempotentMethodsRepeatWhatMayHaveBeenApplied(_ method: HTTPMethod, _ error: APIError<Void>) {
        #expect(error.isRetryable(for: method))
    }

    @Test(arguments: nonIdempotent, mayHaveBeenApplied)
    func nonIdempotentMethodsDoNotRepeatWhatMayHaveBeenApplied(_ method: HTTPMethod, _ error: APIError<Void>) {
        #expect(!error.isRetryable(for: method))
    }

    @Test(arguments: idempotent + nonIdempotent)
    func everyMethodRepeatsWhatNeverLeftTheDevice(_ method: HTTPMethod) {
        #expect(APIError<Void>.transport(.network(URLError(.notConnectedToInternet))).isRetryable(for: method))
    }
}

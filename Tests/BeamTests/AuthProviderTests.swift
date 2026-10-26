//
//  AuthProviderTests.swift
//  Beam
//
//  Verifies that the typed `AuthProtocol` failures reach callers as `APIError`.
//

import Foundation
import Testing
@testable import Beam

@Suite
struct AuthProviderTests {

    private func makeEndpoint(auth: any AuthProtocol, session: MockSession) -> Endpoint<ResponseMock, Void> {
        Endpoint<ResponseMock, Void>(
            session: session,
            auth: auth,
            config: RequestConfig(retry: .none),
            api: APIRequest(method: .get, host: "https://base-url.com", path: "/signed")
        )
    }

    @Test
    func signedAuthAppliesSignature() async throws {
        let body = json(ResponseMock(id: "signed", value: 1))
        let session = MockSession({ (request) throws(URLError) in
            #expect(request.value(forHTTPHeaderField: "X-Signature") == "abc")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (body, response)
        })
        let auth = SignedAuth { (request: inout URLRequest) async throws(AuthError) in
            request.setValue("abc", forHTTPHeaderField: "X-Signature")
        }

        let result = try await makeEndpoint(auth: auth, session: session).data()
        #expect(result.id == "signed")
    }

    @Test
    func signedAuthFailureSurfacesAsAPIErrorWithoutSendingRequest() async {
        let session = MockSession({ (request) throws(URLError) in
            Issue.record("The request must not be sent when signing fails")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })
        let auth = SignedAuth { (_: inout URLRequest) async throws(AuthError) in
            throw .missingToken
        }

        do {
            _ = try await makeEndpoint(auth: auth, session: session).data()
            Issue.record("Should have thrown")
        } catch {
            #expect(error == .missingToken)
        }
    }
}

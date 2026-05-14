//
//  NetworkTests.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 27/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import Foundation
import Testing
@testable import NetworkActor

struct NetworkTests {
    private let mockConfig: URLSessionConfiguration = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return config
    }()
    
    private let defaultEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let defaultDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Test func requestSuccess() async throws {
        let api = ServicePayload(method: .get,
                                 baseURL: "https://base-url.com",
                                 path: "/ok",
                                 headers: ContentType.json().header)
        let endpoint = EndpointMock(endpoint: api)

        let responseBody = ResponseMock(id: "my-id", value: 0)
        guard let responseData = try? defaultEncoder.encode(responseBody) else {
            #expect(Bool(false))
            return
        }

        URLProtocolStub.addStub(endpoint: endpoint) {
            let urlResponse = HTTPURLResponse(url: endpoint.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return StubResponse(data: responseData, response: urlResponse, error: nil)
        }

        let service = ServiceManager(network: .init(configuration: mockConfig), api: endpoint.api)
        
        let result: Result<ResponseMock, ServiceError<Void>> = await service.request()
        switch result {
        case .success: #expect(true)
        case .failure: #expect(Bool(false))
        }
    }
    
    @Test
    func requestFailure() async throws {
        let api = ServicePayload(method: .get,
                                 baseURL: "https://base-url.com",
                                 path: "/error",
                                 headers: ContentType.json().header)
        let endpoint = EndpointMock(endpoint: api)
        
        URLProtocolStub.addStub(endpoint: endpoint) {
            let urlResponse = HTTPURLResponse(url: endpoint.url!, statusCode: 500, httpVersion: nil, headerFields: nil)
            return StubResponse(data: nil, response: urlResponse, error: nil)
        }
        
        let service = ServiceManager(network: .init(configuration: mockConfig), api: endpoint.api)
        
        let result: Result<Void, ServiceError<Void>> = await service.request()
        switch result {
        case .success(_): #expect(Bool(false))
        case .failure(_): #expect(Bool(true))
        }
    }
}

private struct ResponseMock: Codable, Equatable {
    let id: String
    let value: Int
}


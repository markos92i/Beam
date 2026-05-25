//
//  NetworkTests.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 27/3/25.
//

import Foundation
import Testing
@testable import NetworkActor

struct NetworkTests {
    private let mockSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
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
                                 host: "https://base-url.com",
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
            return StubResponse(data: responseData, response: urlResponse)
        }
        
        let service = Service<ResponseMock, ServiceError<Void>>(network: .init(session: mockSession), api: endpoint.api)
        
        let response: ResponseMock = try await service.request()
        #expect(response.id == "my-id")
        #expect(response.value == 0)
    }
    
    @Test
    func requestFailure() async throws {
        let api = ServicePayload(method: .get,
                                 host: "https://base-url.com",
                                 path: "/error",
                                 headers: ContentType.json().header)
        let endpoint = EndpointMock(endpoint: api)
        
        URLProtocolStub.addStub(endpoint: endpoint) {
            let urlResponse = HTTPURLResponse(url: endpoint.url!, statusCode: 500, httpVersion: nil, headerFields: nil)
            return StubResponse(data: nil, response: urlResponse)
        }
        
        let service = Service<ResponseMock, ServiceError<Void>>(network: .init(session: mockSession), api: endpoint.api)
        
        do {
            let _: ResponseMock = try await service.request()
            #expect(Bool(false))
        } catch {
            #expect(true)
        }
    }
    
    @Test
    func uploadSuccess() async throws {
        let api = ServicePayload(method: .post,
                                 host: "https://base-url.com",
                                 path: "/upload",
                                 headers: [:],
                                 body: .data("Dummy file content".data(using: .utf8)!))
        let endpoint = EndpointMock(endpoint: api)
        
        // El mock de respuesta (lo que nos devuelve el servidor tras subir)
        let responseBody = ResponseMock(id: "upload-id", value: 100)
        let responseData = try defaultEncoder.encode(responseBody)
        
        URLProtocolStub.addStub(endpoint: endpoint) {
            let urlResponse = HTTPURLResponse(url: endpoint.url!, statusCode: 201, httpVersion: nil, headerFields: nil)
            return StubResponse(data: responseData, response: urlResponse)
        }
                
        let service = Service<ResponseMock, ServiceError<Void>>(network: .init(session: mockSession), api: endpoint.api)
        
        let response: ResponseMock = try await service.upload()
        #expect(response.id == "upload-id")
        #expect(response.value == 100)
    }
    
    @Test
    func downloadSuccess() async throws {
        let api = ServicePayload(method: .get,
                                 host: "https://base-url.com",
                                 path: "/download",
                                 headers: [:])
        let endpoint = EndpointMock(endpoint: api)
        
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!
        
        URLProtocolStub.addStub(endpoint: endpoint) {
            let urlResponse = HTTPURLResponse(url: endpoint.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return StubResponse(data: expectedDownloadedData, response: urlResponse)
        }
        
        let service = Service<URL, ServiceError<Void>>(network: .init(session: mockSession), api: endpoint.api)
        
        let response: URL = try await service.download()
        let dataFromFile = try Data(contentsOf: response)
        #expect(dataFromFile == expectedDownloadedData)

        try? FileManager.default.removeItem(at: response)
    }
    
    @Test
    func requestOnlineMock() async throws {
        struct TestService: ServiceProtocol {
            var service: Service<ResponseOnlineMock, Void>
            
            init() {
                let payload = ServicePayload(method: .get,
                                             host: "https://jsonplaceholder.typicode.com",
                                             path: "/todos/1",
                                             headers: ContentType.json().header)
                
                self.service = .init(network: .init(),
                                     auth: nil,
                                     crash: nil,
                                     api: payload)
            }
        }
        
        do {
            let service = TestService()
            let _: ResponseOnlineMock = try await service.request()
            #expect(true)
        } catch {
            #expect(Bool(false))
        }
    }
    
    
}

private struct ResponseMock: Codable, Equatable {
    let id: String
    let value: Int
}

private struct ResponseOnlineMock: Codable, Equatable {
    let id: Int
    let userId: Int
    let title: String
    let completed: Bool
}


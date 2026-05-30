//
//  NetworkTests.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 27/3/25.
//

import Foundation
import Testing
@testable import NetworkActor

@Suite
struct NetworkTests {
    @Test
    func requestSuccess() async throws {
        let mockBody = ResponseMock(id: "123", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)
                
        let api = ServicePayload(method: .get,
                                 host: "https://base-url.com",
                                 path: "/ok",
                                 headers: ContentType.json().header)

        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        }
        let networkClient = NetworkClient(session: MockSession(responseStub))
        let service = Service<ResponseMock, ServiceError<Void>>(network: networkClient, api: api)

        let result: ResponseMock = try await service.request()
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }
    
    @Test
    func requestFailure() async throws {
        let api = ServicePayload(method: .get,
                                 host: "https://base-url.com",
                                 path: "/error",
                                 headers: ContentType.json().header)

        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let networkClient = NetworkClient(session: MockSession(responseStub))
        let service = Service<ResponseMock, ServiceError<Void>>(network: networkClient, api: api)

        do {
            let _: ResponseMock = try await service.request()
            #expect(Bool(false))
        } catch {
            #expect(true)
        }
    }
    
    @Test
    func uploadSuccess() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)
                
        let api = ServicePayload(method: .get,
                                 host: "https://base-url.com",
                                 path: "/upload",
                                 headers: [:],
                                 body: .data("Dummy file content".data(using: .utf8)!))

        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        }
        let networkClient = NetworkClient(session: MockSession(responseStub))
        let service = Service<ResponseMock, ServiceError<Void>>(network: networkClient, api: api)

        let result: ResponseMock = try await service.upload()
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }
    
    @Test
    func uploadURLSuccess() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try expectedData.write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
                
        let api = ServicePayload(method: .get,
                                 host: "https://base-url.com",
                                 path: "/upload",
                                 headers: [:],
                                 body: .data("Dummy file content".data(using: .utf8)!))
        
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            let data = try Data(contentsOf: temporaryURL)
            return (data, response)
        }
        let networkClient = NetworkClient(session: MockSession(responseStub))
        let service = Service<ResponseMock, ServiceError<Void>>(network: networkClient, api: api)

        let result: ResponseMock = try await service.upload(url: temporaryURL)
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }
    
    @Test
    func uploadResumeSuccess() async throws {
        let expectedResponse = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(expectedResponse)

        let resumeData = "{ resume: true }".data(using: .utf8)!
        
        let api = ServicePayload(method: .put,
                                 host: "https://base-url.com",
                                 path: "/upload",
                                 headers: [:],
                                 body: .data("Dummy file content".data(using: .utf8)!))

        let resumeStub: (@Sendable (Data) async throws -> (Data, URLResponse))? = { data in
            let response = HTTPURLResponse(url: URL(string: "https://base-url.com")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            #expect(data == resumeData)
            return (expectedData, response)
        }
        let networkClient = NetworkClient(session: MockSession(nil, resumeStub))
        let service = Service<ResponseMock, ServiceError<Void>>(network: networkClient, api: api)

        let result: ResponseMock = try await service.upload(resumeFrom: resumeData)
        #expect(result.id == expectedResponse.id)
        #expect(result.value == expectedResponse.value)
    }

    @Test
    func downloadSuccess() async throws {
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!
                
        let api = ServicePayload(method: .get,
                                 host: "https://base-url.com",
                                 path: "/download",
                                 headers: [:])

        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedDownloadedData, response)
        }
        let networkClient = NetworkClient(session: MockSession(responseStub))
        let service = Service<ResponseMock, ServiceError<Void>>(network: networkClient, api: api)

        let response: URL = try await service.download()
        let dataFromFile = try Data(contentsOf: response)
        #expect(dataFromFile == expectedDownloadedData)

        try? FileManager.default.removeItem(at: response)
    }
    
    @Test
    func downloadResumeSuccess() async throws {
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!
        let resumeData = "{ resume: true }".data(using: .utf8)!

        let api = ServicePayload(method: .get,
                                 host: "https://base-url.com",
                                 path: "/download",
                                 headers: [:])

        let resumeStub: (@Sendable (Data) async throws -> (Data, URLResponse))? = { data in
            let response = HTTPURLResponse(url: URL(string: "https://base-url.com")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            #expect(data == resumeData)
            return (expectedDownloadedData, response)
        }
        let networkClient = NetworkClient(session: MockSession(nil, resumeStub))
        let service = Service<ResponseMock, ServiceError<Void>>(network: networkClient, api: api)

        let response: URL = try await service.download(resumeFrom: resumeData)
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


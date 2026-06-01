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
                
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        }
        struct TestEndpoint: Endpoint {
            let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Get("https://base-url.com", "/ok")
                Use(NetworkClient(session: MockSession(responseStub)))
            }
        }
        
        let service = TestEndpoint(responseStub: responseStub)

        let result: ResponseMock = try await service.data()
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }
    
    @Test
    func requestFailure() async throws {
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        struct TestEndpoint: Endpoint {
            let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Get("https://base-url.com", "/error")
                Use(NetworkClient(session: MockSession(responseStub)))
            }
        }
        
        let service = TestEndpoint(responseStub: responseStub)

        do {
            let _: ResponseMock = try await service.data()
            #expect(Bool(false))
        } catch {
            #expect(true)
        }
    }
    
    @Test
    func uploadSuccess() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)
                
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        }
        struct TestEndpoint: Endpoint {
            let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Get("https://base-url.com", "/upload")
                Use(NetworkClient(session: MockSession(responseStub)))
            }
        }
        
        let service = TestEndpoint(responseStub: responseStub)

        let result: ResponseMock = try await service.upload()
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }
    
    @Test
    func uploadCancel() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)
                
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        }
        
        struct TestEndpoint: Endpoint {
            let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Get("https://base-url.com", "/upload")
                Use(NetworkClient(session: MockSession(responseStub, delay: 1)))
            }
        }
        
        let service = TestEndpoint(responseStub: responseStub)
        
        do {
            Task {
                try await Task.sleep(for: .seconds(0))
                let _ = await service.cancel()
            }
            
            let _ = try await service.upload()
            #expect(Bool(false))
        } catch {
            #expect(error == .cancelled)
        }
    }
    
    @Test
    func uploadTaskCancel() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)
                
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        }
        struct TestEndpoint: Endpoint {
            let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Post("https://base-url.com", "/upload")
                Body(.data("Dummy file content".data(using: .utf8)!))
                Use(NetworkClient(session: MockSession(responseStub, delay: 1)))
            }
        }
        
        let service = TestEndpoint(responseStub: responseStub)

        do {
            let job = Task { try await service.upload() }

            Task {
                try await Task.sleep(for: .seconds(0.05))
                job.cancel()
            }
            
            let _ = try await job.value
            #expect(Bool(false))
        } catch {
            #expect(error is ServiceError<Void>)
        }
    }

    @Test
    func uploadURLSuccess() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try expectedData.write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
                
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            let data = try Data(contentsOf: temporaryURL)
            return (data, response)
        }
        struct TestEndpoint: Endpoint {
            let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Post("https://base-url.com", "/upload")
                Body(.data("Dummy file content".data(using: .utf8)!))
                Use(NetworkClient(session: MockSession(responseStub)))
            }
        }
        
        let service = TestEndpoint(responseStub: responseStub)

        let result: ResponseMock = try await service.upload(url: temporaryURL)
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }
    
    @Test
    func uploadResumeSuccess() async throws {
        let expectedResponse = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(expectedResponse)

        let resumeData = "{ resume: true }".data(using: .utf8)!
        
        let resumeStub: (@Sendable (Data) async throws -> (Data, URLResponse))? = { data in
            let response = HTTPURLResponse(url: URL(string: "https://base-url.com")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            #expect(data == resumeData)
            return (expectedData, response)
        }

        struct TestEndpoint: Endpoint {
            let resumeStub: (@Sendable (Data) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Get("https://base-url.com", "/upload")
                Use(NetworkClient(session: MockSession(nil, resumeStub)))
            }
        }
        
        let service = TestEndpoint(resumeStub: resumeStub)

        let result: ResponseMock = try await service.upload(resumeFrom: resumeData)
        #expect(result.id == expectedResponse.id)
        #expect(result.value == expectedResponse.value)
    }

    @Test
    func downloadSuccess() async throws {
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!
                
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedDownloadedData, response)
        }
        struct TestEndpoint: Endpoint {
            let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Get("https://base-url.com", "/download")
                Use(NetworkClient(session: MockSession(responseStub)))
            }
        }
        
        let service = TestEndpoint(responseStub: responseStub)

        let response: URL = try await service.download()
        let dataFromFile = try Data(contentsOf: response)
        #expect(dataFromFile == expectedDownloadedData)

        try? FileManager.default.removeItem(at: response)
    }
    
    @Test
    func downloadCancel() async throws {
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!
                
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedDownloadedData, response)
        }
        struct TestEndpoint: Endpoint {
            let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Get("https://base-url.com", "/download")
                Use(NetworkClient(session: MockSession(responseStub, delay: 1)))
            }
        }
        
        let service = TestEndpoint(responseStub: responseStub)

        do {
            Task {
                try await Task.sleep(for: .seconds(0))
                let _ = await service.cancel()
            }
            
            let response = try await service.download()
            #expect(Bool(false))
            try? FileManager.default.removeItem(at: response)
        } catch {
            #expect(error == .cancelled)
        }
    }
    
    @Test
    func downloadTaskCancel() async throws {
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!
                
        let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedDownloadedData, response)
        }
        struct TestEndpoint: Endpoint {
            let responseStub: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Get("https://base-url.com", "/download")
                Use(NetworkClient(session: MockSession(responseStub, delay: 1)))
            }
        }
        
        let service = TestEndpoint(responseStub: responseStub)

        do {
            let job = Task { try await service.download() }

            Task {
                try await Task.sleep(for: .seconds(0.5))
                job.cancel()
            }
            
            let response = try await job.value
            #expect(Bool(false))
            try? FileManager.default.removeItem(at: response)
        } catch {
            #expect(error is ServiceError<Void>)
        }
    }

    @Test
    func downloadResumeSuccess() async throws {
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!
        let resumeData = "{ resume: true }".data(using: .utf8)!

        let resumeStub: (@Sendable (Data) async throws -> (Data, URLResponse))? = { data in
            let response = HTTPURLResponse(url: URL(string: "https://base-url.com")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            #expect(data == resumeData)
            return (expectedDownloadedData, response)
        }

        struct TestEndpoint: Endpoint {
            let resumeStub: (@Sendable (Data) async throws -> (Data, URLResponse))?
            
            var service: Service<ResponseMock, Void> {
                Get("https://base-url.com", "/download")
                Use(NetworkClient(session: MockSession(nil, resumeStub)))
            }
        }
        
        let service = TestEndpoint(resumeStub: resumeStub)

        let response: URL = try await service.download(resumeFrom: resumeData)
        let dataFromFile = try Data(contentsOf: response)
        #expect(dataFromFile == expectedDownloadedData)

        try? FileManager.default.removeItem(at: response)
    }

    @Test
    func requestOnline() async throws {
        struct TestEndpoint: Endpoint {
            var service: Service<ResponseOnlineMock, Void> {
                Get("https://jsonplaceholder.typicode.com", "/todos/1")
            }
        }
        
        let service = TestEndpoint()

        do {
            let _: ResponseOnlineMock = try await service.data()
            #expect(true)
        } catch {
            #expect(Bool(false))
        }
    }
    
    @Test
    func requestOnlineCancel() async throws {
        struct TestEndpoint: Endpoint {
            var service: Service<ResponseOnlineMock, Void> {
                Get("https://jsonplaceholder.typicode.com", "/todos/1")
            }
        }
        
        let service = TestEndpoint()

        do {
            Task {
                try await Task.sleep(for: .seconds(0.05))
                let _ = await service.cancel()
            }
            let _: ResponseOnlineMock = try await service.data()
            #expect(Bool(false))
        } catch {
            #expect(error == .cancelled)
        }
    }
    
    @Test
    func requestOnlineTaskCancel() async throws {
        struct TestEndpoint: Endpoint {
            var service: Service<ResponseOnlineMock, Void> {
                Get("https://jsonplaceholder.typicode.com", "/todos/1")
            }
        }
        
        let service = TestEndpoint()

        do {
            let job = Task { try await service.data() }

            Task {
                try await Task.sleep(for: .seconds(0.05))
                job.cancel()
            }
            
            let _: ResponseOnlineMock = try await job.value
            #expect(Bool(false))
        } catch {
            #expect(error is ServiceError<Void>)
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



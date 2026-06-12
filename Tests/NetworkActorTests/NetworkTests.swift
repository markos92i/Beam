//
//  NetworkTests.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 27/3/25.
//

import Foundation
import Testing
@testable import NetworkActor

// MARK: - Test Endpoints

private struct RequestEndpoint: Endpoint {
    let session: any NetworkSession

    var task: DataTask<ResponseMock, Void> {
        Get("https://base-url.com", "/ok")
        Use(Client(session: session))
    }
}

private struct UploadEndpoint: Endpoint {
    let session: any NetworkSession

    var task: UploadTask<ResponseMock, Void> {
        Get("https://base-url.com", "/upload")
        Body(.data("Dummy file content".data(using: .utf8)!))
        Use(Client(session: session))
    }
}

private struct DownloadEndpoint: Endpoint {
    let session: any NetworkSession

    var task: DownloadTask<Void> {
        Get("https://base-url.com", "/download")
        Use(Client(session: session))
    }
}

private struct OnlineEndpoint: Endpoint {
    var task: DataTask<ResponseOnlineMock, Void> {
        Get("https://jsonplaceholder.typicode.com", "/todos/1")
    }
}

// MARK: - Tests

@Suite
struct NetworkTests {

    @Test
    func requestSuccess() async throws {
        let mockBody = ResponseMock(id: "123", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let result = try await RequestEndpoint(session: session).call()
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }

    @Test
    func requestFailure() async throws {
        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })

        do {
            _ = try await RequestEndpoint(session: session).call()
            #expect(Bool(false))
        } catch {
            #expect(true)
        }
    }

    @Test
    func uploadSuccess() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        })

        let result = try await UploadEndpoint(session: session).call()
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }

    @Test
    func uploadCancel() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        }, nil, delay: 2)

        let endpoint = UploadEndpoint(session: session)

        do {
            Task {
                try await Task.sleep(for: .seconds(0))
                await endpoint.cancel()
            }
            _ = try await endpoint.call()
            #expect(Bool(false))
        } catch {
            #expect(error == .cancelled)
        }
    }

    @Test
    func uploadTaskCancel() async throws {
        let mockBody = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(mockBody)

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (expectedData, response)
        }, nil, delay: 2)

        let endpoint = UploadEndpoint(session: session)

        do {
            let job = Task { try await endpoint.call() }
            Task {
                try await Task.sleep(for: .seconds(0.5))
                job.cancel()
            }
            _ = try await job.value
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

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            let data = try Data(contentsOf: temporaryURL)
            return (data, response)
        })

        let result = try await UploadEndpoint(session: session).call(url: temporaryURL)
        #expect(result.id == mockBody.id)
        #expect(result.value == mockBody.value)
    }

    @Test
    func uploadResumeSuccess() async throws {
        let expectedResponse = ResponseMock(id: "upload-id", value: 1000)
        let expectedData = try JSONEncoder().encode(expectedResponse)
        let resumeData = "{ resume: true }".data(using: .utf8)!

        let session = MockSession(nil, { data in
            let response = HTTPURLResponse(url: URL(string: "https://base-url.com")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            #expect(data == resumeData)
            return (expectedData, response)
        })

        let result = try await UploadEndpoint(session: session).call(resumeFrom: resumeData)
        #expect(result.id == expectedResponse.id)
        #expect(result.value == expectedResponse.value)
    }

    @Test
    func downloadSuccess() async throws {
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedDownloadedData, response)
        })

        let response = try await DownloadEndpoint(session: session).call()
        let dataFromFile = try Data(contentsOf: response)
        #expect(dataFromFile == expectedDownloadedData)
        try? FileManager.default.removeItem(at: response)
    }

    @Test
    func downloadCancel() async throws {
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedDownloadedData, response)
        }, nil, delay: 2)

        let endpoint = DownloadEndpoint(session: session)

        do {
            Task {
                try await Task.sleep(for: .seconds(0))
                await endpoint.cancel()
            }
            let response = try await endpoint.call()
            #expect(Bool(false))
            try? FileManager.default.removeItem(at: response)
        } catch {
            #expect(error == .cancelled)
        }
    }

    @Test
    func downloadTaskCancel() async throws {
        let expectedDownloadedData = "Downloaded file content".data(using: .utf8)!

        let session = MockSession({ request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (expectedDownloadedData, response)
        }, nil, delay: 2)

        let endpoint = DownloadEndpoint(session: session)

        do {
            let job = Task { try await endpoint.call() }
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

        let session = MockSession(nil, { data in
            let response = HTTPURLResponse(url: URL(string: "https://base-url.com")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            #expect(data == resumeData)
            return (expectedDownloadedData, response)
        })

        let response = try await DownloadEndpoint(session: session).call(resumeFrom: resumeData)
        let dataFromFile = try Data(contentsOf: response)
        #expect(dataFromFile == expectedDownloadedData)
        try? FileManager.default.removeItem(at: response)
    }

    @Test
    func requestOnline() async throws {
        do {
            _ = try await OnlineEndpoint().call()
            #expect(true)
        } catch {
            #expect(Bool(false))
        }
    }

    @Test
    func requestOnlineCancel() async throws {
        let endpoint = OnlineEndpoint()

        do {
            Task {
                try await Task.sleep(for: .seconds(0.05))
                await endpoint.cancel()
            }
            _ = try await endpoint.call()
            #expect(Bool(false))
        } catch {
            #expect(error == .cancelled)
        }
    }

    @Test
    func requestOnlineTaskCancel() async throws {
        let endpoint = OnlineEndpoint()

        do {
            let job = Task { try await endpoint.call() }
            Task {
                try await Task.sleep(for: .seconds(0.05))
                job.cancel()
            }
            _ = try await job.value
            #expect(Bool(false))
        } catch {
            #expect(error is ServiceError<Void>)
        }
    }
}

// MARK: - Mocks

private struct ResponseMock: Codable, Equatable, Sendable {
    let id: String
    let value: Int
}

private struct ResponseOnlineMock: Codable, Equatable, Sendable {
    let id: Int
    let userId: Int
    let title: String
    let completed: Bool
}

//
//  NetworkActor.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Protocol Definition
protocol NetworkProtocol: Actor {
    func request(api: APIEndpoint) async throws -> Data
    func upload(api: APIEndpoint, data: Data) async throws -> Data
    func download(api: APIEndpoint) async throws -> URL
    
    var progress: AsyncStream<Progress> { get }
}

public actor NetworkActor: NetworkProtocol {
    let uuid = UUID().uuidString
    
    public static let queue = NetworkQueue()
    
    private let delegate: NetworkDelegate
    private let session: URLSession
    
    private let progressContinuation: AsyncStream<Progress>.Continuation
    let progress: AsyncStream<Progress>
    
    public static let config: URLSessionConfiguration = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.urlCache = nil
        return config
    }()

    public init(
        configuration: URLSessionConfiguration = config,
        certificates: [Data] = []
    ) {
        let (stream, continuation) = AsyncStream<Progress>.makeStream()
        self.progress = stream
        self.progressContinuation = continuation

        self.delegate = .init(certificates: certificates, continuation: continuation)
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    
    deinit {
        progressContinuation.finish()
    }
    
    private func executeOperation<T>(
        api: APIEndpoint,
        operation: (URLRequest) async throws -> (T, URLResponse)
    ) async throws(NetworkError) -> (T, HTTPURLResponse) {
        guard let request = api.urlRequest else { throw .invalidURL }
        
        debug("request path: [\(api.method)] \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody {
            debug("request body: \(String(data: body, encoding: .utf8) ?? "")")
        }
        
        do {
            let (responseData, response) = try await operation(request)
            await NetworkActor.queue.remove(session)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.noResponse
            }
            
            debug("response statusCode: \(httpResponse.statusCode)")
            
            return (responseData, httpResponse)
        } catch let error as URLError {
            await NetworkActor.queue.remove(session)
            throw .url(error, code: error.code)
        } catch let error as NetworkError {
            await NetworkActor.queue.remove(session)
            throw error
        } catch {
            await NetworkActor.queue.remove(session)
            throw .unknown
        }
    }
    
    // MARK: - Public API
    public func request(api: APIEndpoint) async throws(NetworkError) -> Data {
        let (data, response) = try await executeOperation(api: api) { request in
            try await session.data(for: request)
        }
        
        debug("response body: \(prettyJson(data: data) ?? "")")
        guard (200...299).contains(response.statusCode) else { throw .http(code: response.statusCode, data: data) }
        
        return data
    }
    
    public func upload(api: APIEndpoint, data: Data) async throws(NetworkError) -> Data {
        let (responseData, response) = try await executeOperation(api: api) { request in
            try await session.upload(for: request, from: data)
        }
        
        guard (200...299).contains(response.statusCode) else { throw .http(code: response.statusCode, data: responseData) }

        return responseData
    }
    
    public func download(api: APIEndpoint) async throws(NetworkError) -> URL {
        let (url, response) = try await executeOperation(api: api) { request in
            try await session.download(for: request)
        }
        
        guard (200...299).contains(response.statusCode) else { throw .http(code: response.statusCode, data: nil) }
        
        do {
            return try FileUtils.copy(url: url, to: .cachesDirectory, contentType: response.contentType)
        } catch {
            throw NetworkError(fileError: error)
        }
    }

    public func cancel() async {
        await NetworkActor.queue.cancel(session)
    }

    // MARK: - Private Helpers
    private func debug(_ text: String) {
        print("[LOG] Network ID[\(uuid)]: \(text)")
    }
        
    private func prettyJson(data: Data) -> NSString? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let prettyPrintedString = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else {
            return NSString(data: data, encoding: String.Encoding.utf8.rawValue)
        }

        return prettyPrintedString
    }
}

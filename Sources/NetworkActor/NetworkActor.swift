//
//  NetworkActor.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 6/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
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

    // MARK: - Public API (Throwing only)

    public func request(api: APIEndpoint) async throws -> Data {
        guard let request = api.urlRequest else { throw NetworkError(type: .invalidURL) }
        
        debug("request path: \(api.method): \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody {
            debug("request body: \(String(data: body, encoding: .utf8) ?? "")")
        }

        do {
            let (data, response) = try await session.data(for: request)
            await NetworkActor.queue.remove(session)
            
            debug("response body: \(prettyJson(data: data) ?? "")")
            
            return try validateResponse(response: response, data: data)
        } catch {
            throw mapError(error)
        }
    }

    public func upload(api: APIEndpoint, data: Data) async throws -> Data {
        guard let request = api.urlRequest else { throw NetworkError(type: .invalidURL) }

        debug("upload path: \(api.method): \(request.url?.absoluteString ?? "")")
        debug("upload data: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")...")

        do {
            let (responseData, response) = try await session.upload(for: request, from: data)
            await NetworkActor.queue.remove(session)
            
            return try validateResponse(response: response, data: responseData)
        } catch {
            throw mapError(error)
        }
    }

    public func download(api: APIEndpoint) async throws -> URL {
        guard let request = api.urlRequest else { throw NetworkError(type: .invalidURL) }

        debug("download path: \(api.method): \(request.url?.absoluteString ?? "")")

        do {
            let (url, response) = try await session.download(for: request)
            await NetworkActor.queue.remove(session)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError(type: .noResponse)
            }
            
            debug("download response statusCode: \(httpResponse.statusCode)")
            
            switch httpResponse.statusCode {
            case 200...299:
                guard let contentType = httpResponse.contentType else {
                    throw NetworkError(type: .unknown)
                }
                
                return try save(url: url, contentType: contentType)
                
            case 400: throw NetworkError(type: .badRequest)
            case 401: throw NetworkError(type: .unauthorized)
            case 403: throw NetworkError(type: .forbidden)
            case 404: throw NetworkError(type: .notFound)
            case 409: throw NetworkError(type: .conflict)
            case 500...599: throw NetworkError(type: .serverError)
            default:  throw NetworkError(type: .unexpectedCode)
            }
        } catch {
            throw mapError(error)
        }
    }

    public func cancel() async {
        await NetworkActor.queue.cancel(session)
    }

    // MARK: - Private Helpers
    
    private func validateResponse(response: URLResponse, data: Data) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError(type: .noResponse)
        }

        debug("response statusCode: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 400:
            throw NetworkError(type: .badRequest, body: data)
        case 401:
            throw NetworkError(type: .unauthorized, body: data)
        case 403:
            throw NetworkError(type: .forbidden, body: data)
        case 404:
            throw NetworkError(type: .notFound, body: data)
        case 409:
            throw NetworkError(type: .conflict, body: data)
        case 500...599:
            throw NetworkError(type: .serverError, body: data)
        default:
            throw NetworkError(type: .unexpectedCode, body: data)
        }
    }
    
    private func mapError(_ error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        }
        
        // Errores de URLSession (Conectividad, DNS, SSL)
        guard let urlError = error as? URLError else {
            return .init(type: .unknown)
        }
        
        switch urlError.code {
        case .timedOut:
            return .init(type: .timedOut)
        case .cancelled:
            return .init(type: .canceled)
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .init(type: .noConnection)
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted:
            return .init(type: .sslError)
        case .cannotFindHost, .dnsLookupFailed:
            return .init(type: .serverError)
        default:
            return .init(type: .unknown)
        }
    }
        
    private func debug(_ text: String) {
        print("[LOG] Network ID[\(uuid)]: \(text)")
    }
    
    private func save(url: URL, contentType: String) throws -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let sub = contentType.split(separator: "/").last
        let ext = UTType(mimeType: contentType)?.preferredFilenameExtension ?? String(sub ?? "")
        
        guard let target = cachesDir?.appendingPathComponent("\(UUID().uuidString).\(ext)") else {
            throw NetworkError(type: .storage)
        }

        if FileManager.default.fileExists(atPath: target.path()) {
            try FileManager.default.removeItem(at: target)
        }
        
        try FileManager.default.copyItem(at: url, to: target)
        return target
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

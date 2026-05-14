//
//  ServiceManager.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 12/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import SwiftUI

public struct ServiceManager: Sendable {
    public var network: NetworkActor
    public var auth: AuthProtocol? = nil
    public var crash: CrashProtocol? = nil
    public var api: ServicePayload
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder
    
    public static let defaultEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let defaultDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    public init(
        network: NetworkActor,
        auth: (any AuthProtocol)? = nil,
        crash: CrashProtocol? = nil,
        api: ServicePayload,
        encoder: JSONEncoder = defaultEncoder,
        decoder: JSONDecoder = defaultDecoder
    ) {
        self.network = network
        self.auth = auth
        self.crash = crash
        self.api = api
        self.encoder = encoder
        self.decoder = decoder
    }

    @concurrent public func cache<Success: Sendable, Failure: Sendable>(file: String) async -> Result<Success, ServiceError<Failure>> {
        guard let url = Bundle.main.url(forResource: file, withExtension: nil),
              let data = try? Data(contentsOf: url),
              let decoded: Success = decode(data: data) else { return .failure(.init(type: .decode)) }

        return .success(decoded)
    }

    // MARK: - Throwing Core Implementation
    @concurrent public func request<Success: Sendable, Failure: Sendable>(
        failureType: Failure.Type = Failure.self
    ) async throws(ServiceError<Failure>) -> Success {
        let api = prepare(payload: api)
        guard let authenticatedApi = await auth(api: api) else {
            throw ServiceError<Failure>(type: .unauthorized)
        }

        do {
            let data: Data = try await network.request(api: authenticatedApi)
            
            guard let decoded: Success = decode(data: data) else {
                throw ServiceError<Failure>(type: .decode)
            }
            return decoded
        } catch {
            inspectAndReport(error)
            throw mapToServiceError(error: error, type: Failure.self)
        }
    }
    
    @concurrent public func upload<Success: Sendable, Failure: Sendable>(
        failureType: Failure.Type = Failure.self
    ) async throws(ServiceError<Failure>) -> Success {
        let api = prepare(payload: api)
        guard let authenticatedApi = await auth(api: api) else {
            throw ServiceError<Failure>(type: .unauthorized)
        }

        do {
            let data: Data = try await network.upload(api: authenticatedApi, data: api.data ?? Data())
            
            guard let decoded: Success = decode(data: data) else {
                throw ServiceError<Failure>(type: .decode)
            }
            return decoded
        } catch {
            inspectAndReport(error)
            throw mapToServiceError(error: error, type: Failure.self)
        }
    }
    
    @concurrent public func download<Failure: Sendable>(
        failureType: Failure.Type = Failure.self
    ) async throws(ServiceError<Failure>) -> URL {
        let api = prepare(payload: api)
        guard let authenticatedApi = await auth(api: api) else {
            throw ServiceError<Failure>(type: .unauthorized)
        }

        do {
            let url: URL = try await network.download(api: authenticatedApi)
            return url
        } catch {
            inspectAndReport(error)
            throw mapToServiceError(error: error, type: Failure.self)
        }
    }

    // MARK: - Result Wrappers (Backward Compatibility)
    @concurrent public func request<Success: Sendable, Failure: Sendable>() async -> Result<Success, ServiceError<Failure>> {
        do {
            return .success(try await request(failureType: Failure.self))
        } catch {
            return .failure(error)
        }
    }
    
    @concurrent public func upload<Success: Sendable, Failure: Sendable>() async -> Result<Success, ServiceError<Failure>> {
        do {
            return .success(try await upload(failureType: Failure.self))
        } catch {
            return .failure(error)
        }
    }
    
    @concurrent public func download<Failure: Sendable>() async -> Result<URL, ServiceError<Failure>> {
        do {
            return .success(try await download(failureType: Failure.self))
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Private Helpers
    private func mapToServiceError<Failure: Sendable>(error: Error, type: Failure.Type) -> ServiceError<Failure> {
        if let serviceError = error as? ServiceError<Failure> {
            return serviceError
        }
        
        guard let networkError = error as? NetworkError else {
            return ServiceError<Failure>(type: .unknown)
        }
        
        var decodedErrorBody: Failure? = nil
        if let bodyData = networkError.body {
            decodedErrorBody = decode(data: bodyData)
        }
        
        return ServiceError<Failure>(type: networkError.type, body: decodedErrorBody)
    }
    
    private func prepare(payload: ServicePayload) -> APIEndpoint {
        return .init(method: payload.method,
                     baseURL: payload.baseURL,
                     path: payload.path,
                     params: payload.params,
                     headers: payload.headers,
                     body: encode(value: payload.body),
                     data: payload.data,
                     timeout: payload.timeout)
    }
    
    private func encode<Value>(value: Value) -> Data? {
        switch value {
        case let value as Data: return value
        case let value as Codable:
            do {
                return try encoder.encode(value)
            } catch let error as EncodingError {
                switch error {
                case .invalidValue(let key, let value):
                    failure(error, info: ["EncodingError": "invalidValue(key: \(key), value: \(value))"])
                default:
                    failure(error, info: ["EncodingError": "unkown"])
                }
                return nil
            } catch {
                return nil
            }
        case let value as String: return value.data(using: .utf8)
        default: return nil
        }
    }
    
    private func decode<Value>(data: Data) -> Value? {
        switch Value.self {
        case is Data.Type: return data as? Value
        case is Bool.Type: return Bool(String(data: data, encoding: .utf8) ?? "false") as? Value
        case let type as Codable.Type:
            do {
                return try decoder.decode(type, from: data) as? Value
            } catch let error as DecodingError {
                switch error {
                case .typeMismatch(let key, let value):
                    failure(error, info: ["DecodingError": "typeMismatch(key: \(key), value: \(value))"])
                case .valueNotFound(let key, let value):
                    failure(error, info: ["DecodingError": "valueNotFound(key: \(key), value: \(value))"])
                case .keyNotFound(let key, let value):
                    failure(error, info: ["DecodingError": "keyNotFound(key: \(key), value: \(value))"])
                case .dataCorrupted(let key):
                    failure(error, info: ["DecodingError": "dataCorrupted(key: \(key))"])
                default:
                    failure(error, info: ["DecodingError": "unkown"])
                }
                return nil
            } catch {
                return nil
            }
        case is String.Type: return String(data: data, encoding: .utf8) as? Value
        case is UIImage.Type: return UIImage(data: data) as? Value
        case is Void.Type: return () as? Value
        default: return nil
        }
    }

    @concurrent private func auth(api: APIEndpoint) async -> APIEndpoint? {
        guard let auth else { return api }
        
        do {
            var api = api
            api.headers = api.headers.merging(try await auth.authHeader) { $1 }
            return api
        } catch AuthError.missingToken {
            print("AuthError.missingToken")
            return nil
        } catch AuthError.failedToRefreshToken {
            print("AuthError.failedToRefreshToken")
            return nil
        } catch AuthError.invalidCredentials {
            print("AuthError.invalidCredentials")
            return nil
        } catch {
            return nil
        }
    }
    
    @concurrent public func cancel() async {
        await network.cancel()
    }
}

extension ServiceManager {
    fileprivate func inspectAndReport(_ error: Error) {
        if let networkError = error as? NetworkError {
            if shouldIgnore(networkError) { return }

            failure(error, info: ["Error": String(describing: type(of: error))])
        } else {
            failure(error, info: ["Error": String(describing: type(of: error))])
        }
    }
    
    private func shouldIgnore(_ error: NetworkError) -> Bool {
        switch error.type {
        case .canceled: true // Ignore cancelled by user
        default: false
        }
    }

    private func failure(_ error: Error, info: [String: Any]) {
        let requestContext = [
            "URL": (api.url?.absoluteString ?? "Invalid URL")!,
            "Method": api.method.description,
            "RequestBody": String(data: encode(value: api.body) ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A",
            "RequestData": String(data: api.data ?? Data(), encoding: .utf8)?.prefix(2000) ?? "N/A"
        ].merging(info) { $1 }
        
        crash?.report(error: error, userInfo: requestContext)
    }
}

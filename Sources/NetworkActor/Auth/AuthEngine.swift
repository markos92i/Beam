//
//  AuthEngine.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 13/05/2026.
//

import Foundation

public actor AuthEngine<T: AuthToken> {
    public enum State: Sendable {
        case loading
        case ready(T)
        case empty
    }
    
    private var state: State = .loading
    private var authTask: Task<T, Error>?
    private var initContinuation: CheckedContinuation<Void, Never>?

    private let onRefresh: @Sendable () async throws -> T

    public init(onRefresh: @escaping @Sendable () async throws -> T) {
        self.onRefresh = onRefresh
    }

    public func restore(token: T) {
        state = .ready(token)
        resumeInit()
    }

    public func clear() {
        state = .empty
        authTask?.cancel()
        authTask = nil
        resumeInit()
    }

    private func resumeInit() {
        initContinuation?.resume()
        initContinuation = nil
    }

    public func resolveToken() async throws -> T {
        switch state {
        case .ready(let currentToken):
            if currentToken.isValid { return currentToken }
            
            if let authTask { return try await authTask.value }
            
            let task = Task { () throws -> T in
                defer { authTask = nil }
                do {
                    let newToken = try await onRefresh()
                    self.state = .ready(newToken)
                    return newToken
                } catch AuthError.invalidCredentials {
                    self.clear()
                    throw AuthError.invalidCredentials
                } catch {
                    throw error
                }
            }
            authTask = task
            return try await task.value

        case .loading:
            if let authTask { return try await authTask.value }
            
            let task = Task { () throws -> T in
                defer { authTask = nil }
                await withCheckedContinuation { initContinuation = $0 }
                return try await resolveToken()
            }
            authTask = task
            return try await task.value
            
        case .empty:
            throw AuthError.missingToken
        }
    }
}

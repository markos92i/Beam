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
        case invalid
        case empty
    }
    
    private var state: State = .loading
    
    private var refreshTask: Task<T, Error>?
    private var waitTask: Task<T, Error>?
    private var initContinuation: CheckedContinuation<Void, Never>?

    private let onRefresh: @Sendable () async throws -> T

    public init(onRefresh: @escaping @Sendable () async throws -> T) {
        self.onRefresh = onRefresh
    }

    public func set(token: T) {
        state = .ready(token)
        resumeInit()
    }

    public func invalidate() {
        state = .invalid
    }
    
    public func clear() {
        state = .empty
        resumeInit()
        refreshTask?.cancel()
        refreshTask = nil
        waitTask?.cancel()
        waitTask = nil
    }

    private func resumeInit() {
        initContinuation?.resume()
        initContinuation = nil
    }

    public func resolveToken() async throws -> T {
        switch state {
        case .loading:
            return try await wait()

        case .ready(let currentToken):
            if currentToken.isValid { return currentToken }
            return try await refresh()
            
        case .invalid:
            return try await refresh()

        case .empty:
            throw AuthError.missingToken
        }
    }
    
    private func refresh() async throws -> T {
        if let refreshTask { return try await refreshTask.value }

        let task = Task { () throws -> T in
            defer { refreshTask = nil }
            
            do {
                let newToken = try await onRefresh()
                self.state = .ready(newToken)
                return newToken
            } catch AuthError.invalidCredentials {
                self.clear()
                throw AuthError.invalidCredentials
            } catch {
                throw AuthError.unknown
            }
        }
        
        refreshTask = task
        return try await task.value
    }
    
    private func wait() async throws -> T {
        if let waitTask { return try await waitTask.value }
        
        let task = Task { () throws -> T in
            defer { waitTask = nil }
            await withCheckedContinuation { initContinuation = $0 }
            
            return try await resolveToken()
        }
        
        waitTask = task
        return try await task.value
    }
}

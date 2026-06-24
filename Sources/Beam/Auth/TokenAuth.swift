//
//  TokenAuth.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 16/06/2026.
//

import Foundation

/// Auth provider with automatic token refresh, deduplication, and state management.
public actor TokenAuth: AuthProtocol {

    // MARK: - Token

    /// A token with a value and expiration date.
    public struct Token: Sendable {
        /// The raw token value (e.g., JWT string, access token).
        public let value: String

        /// When this token expires. The engine will refresh before using an expired token.
        public let expiration: Date

        /// Whether the token is still usable (not expired).
        public var isValid: Bool { Date.now < expiration }

        public init(value: String, expiration: Date) {
            self.value = value
            self.expiration = expiration
        }

        /// Convenience for tokens expressed as "seconds from now".
        public init(value: String, expiresIn seconds: TimeInterval) {
            self.value = value
            self.expiration = Date.now.addingTimeInterval(seconds)
        }
    }

    // MARK: - State

    private enum State: Sendable {
        case loading
        case ready(Token)
        case invalid
        case empty

        var name: String {
            switch self {
            case .loading: "loading"
            case .ready:   "ready"
            case .invalid: "invalid"
            case .empty:   "empty"
            }
        }
    }

    // MARK: - Properties

    private let name: String
    private let onRefresh: @Sendable () async throws -> Token
    private let applyToken: @Sendable (Token, inout URLRequest) -> Void
    private let log = BeamLogger()

    private var state: State = .loading {
        didSet { log.log(.auth(type: "TokenAuth", name: name, detail: "state → \(state.name)")) }
    }

    private var refreshTask: Task<Token, any Error>?
    private var waitTask: Task<Token, any Error>?
    private var initContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Init

    /// Creates a token-based auth provider with the default Bearer scheme.
    ///
    /// - Parameters:
    ///   - name: Identifier for this auth provider (used in logs).
    ///   - refresh: Called when a new token is needed (expired or invalidated).
    public init(
        name: String = "Auth",
        refresh: @escaping @Sendable () async throws(AuthError) -> Token
    ) {
        self.name = name
        self.onRefresh = refresh
        self.applyToken = { token, request in
            request.addValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Creates a token-based auth provider with custom request application.
    ///
    /// - Parameters:
    ///   - name: Identifier for this auth provider (used in logs).
    ///   - refresh: Called when a new token is needed (expired or invalidated).
    ///   - apply: Closure that applies the resolved token to the outgoing request.
    public init(
        name: String = "Auth",
        refresh: @escaping @Sendable () async throws(AuthError) -> Token,
        apply: @escaping @Sendable (Token, inout URLRequest) -> Void
    ) {
        self.name = name
        self.onRefresh = refresh
        self.applyToken = apply
    }

    // MARK: - AuthProtocol

    public func authenticate(request: inout URLRequest) async throws {
        let token = try await resolveToken()
        applyToken(token, &request)
    }

    public func invalidate() async {
        state = .invalid
    }

    // MARK: - Lifecycle

    /// Sets an initial token (e.g., after login).
    public func set(token: Token) {
        state = .ready(token)
        resumeInit()
    }

    /// Clears the token (e.g., on logout). Subsequent requests will fail with `AuthError.missingToken`.
    public func clear() {
        state = .empty
        resumeInit()
        refreshTask?.cancel()
        refreshTask = nil
        waitTask?.cancel()
        waitTask = nil
    }

    // MARK: - Token Resolution

    private func resolveToken() async throws -> Token {
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

    // MARK: - Refresh

    private func refresh() async throws -> Token {
        if let refreshTask { return try await refreshTask.value }

        let task = Task { () throws -> Token in
            defer { refreshTask = nil }

            self.log.log(.auth(type: "TokenAuth", name: name, detail: "refreshing 􀅈"))

            do {
                let newToken = try await onRefresh()
                self.state = .ready(newToken)
                self.log.log(.auth(type: "TokenAuth", name: name, detail: "refreshed 􀆅"))
                return newToken
            } catch AuthError.invalidCredentials {
                self.clear()
                throw AuthError.invalidCredentials
            } catch is CancellationError {
                throw AuthError.cancelled
            } catch {
                self.state = .invalid
                throw AuthError.failedToRefreshToken
            }
        }

        refreshTask = task
        return try await task.value
    }

    // MARK: - Wait (initial token)

    private func wait() async throws -> Token {
        if let waitTask { return try await waitTask.value }

        let task = Task { () throws -> Token in
            defer { waitTask = nil }
            await withCheckedContinuation { initContinuation = $0 }
            if Task.isCancelled { throw AuthError.cancelled }
            return try await resolveToken()
        }

        waitTask = task
        return try await task.value
    }

    // MARK: - Helpers

    private func resumeInit() {
        initContinuation?.resume()
        initContinuation = nil
    }
}

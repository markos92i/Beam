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

    /// A token and its expiration.
    public struct Token: Sendable {
        /// The raw token (e.g. a JWT).
        public let value: String

        /// An expired token is refreshed before use.
        public let expiration: Date

        /// Whether it hasn't expired.
        public var isValid: Bool { Date.now < expiration }

        public init(value: String, expiration: Date) {
            self.value = value
            self.expiration = expiration
        }

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
    private let onRefresh: @Sendable () async throws(AuthError) -> Token
    private let onSessionLost: (@Sendable () async -> Void)?
    private let applyToken: @Sendable (Token, inout URLRequest) -> Void
    private let log = BeamLogger()

    private var state: State = .loading {
        didSet { log.log(.auth(type: "TokenAuth", name: name, detail: "state → \(state.name)")) }
    }

    // Typed `Result`: `Task` can't carry a typed failure.
    private var refreshTask: Task<Result<Token, AuthError>, Never>?
    private var waitTask: Task<Result<Token, AuthError>, Never>?
    private var initContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Init

    /// Bearer scheme. `name` identifies the provider in logs. `onSessionLost` runs when refresh
    /// fails with `.invalidCredentials`: clear local state there, without network calls.
    public init(
        name: String = "Auth",
        refresh: @escaping @Sendable () async throws(AuthError) -> Token,
        onSessionLost: (@Sendable () async -> Void)? = nil
    ) {
        self.name = name
        self.onRefresh = refresh
        self.onSessionLost = onSessionLost
        self.applyToken = { token, request in
            request.addValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        }
    }

    /// `apply` puts the token on the request instead of the Bearer header.
    public init(
        name: String = "Auth",
        refresh: @escaping @Sendable () async throws(AuthError) -> Token,
        onSessionLost: (@Sendable () async -> Void)? = nil,
        apply: @escaping @Sendable (Token, inout URLRequest) -> Void
    ) {
        self.name = name
        self.onRefresh = refresh
        self.onSessionLost = onSessionLost
        self.applyToken = apply
    }

    // MARK: - AuthProtocol

    public func authenticate(request: inout URLRequest) async throws(AuthError) {
        let token = try await resolveToken()
        applyToken(token, &request)
    }

    public func invalidate() async {
        state = .invalid
        resumeInit()
    }

    // MARK: - Lifecycle

    /// Sets the token (e.g. after login).
    public func set(token: Token) {
        state = .ready(token)
        resumeInit()
    }

    /// Clears the token (e.g. on logout); later requests fail with `.missingToken`.
    public func clear() {
        state = .empty
        resumeInit()
        refreshTask?.cancel()
        refreshTask = nil
        waitTask?.cancel()
        waitTask = nil
    }

    // MARK: - Token Resolution

    private func resolveToken() async throws(AuthError) -> Token {
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

    private func refresh() async throws(AuthError) -> Token {
        if let refreshTask {
            return try await refreshTask.value.get()
        }

        let task = Task(name: "Beam.TokenAuth.refresh") { () -> Result<Token, AuthError> in
            defer { refreshTask = nil }

            self.log.log(.auth(type: "TokenAuth", name: name, detail: "refreshing 􀅈"))

            do throws(AuthError) {
                let newToken = try await onRefresh()
                self.state = .ready(newToken)
                self.log.log(.auth(type: "TokenAuth", name: name, detail: "success 􀆅"))
                return .success(newToken)
            } catch .invalidCredentials {
                self.log.log(.auth(type: "TokenAuth", name: name, detail: "failure 􀆄 invalidCredentials"))
                self.clear()
                await onSessionLost?()
                return .failure(.invalidCredentials)
            } catch .cancelled {
                self.log.log(.auth(type: "TokenAuth", name: name, detail: "failure 􀆄 cancelled"))
                return .failure(.cancelled)
            } catch {
                self.log.log(.auth(type: "TokenAuth", name: name, detail: "failure 􀆄 failedToRefreshToken"))
                self.state = .invalid
                return .failure(.failedToRefreshToken)
            }
        }

        refreshTask = task
        return try await task.value.get()
    }

    // MARK: - Wait (initial token)

    private func wait() async throws(AuthError) -> Token {
        if let waitTask { return try await waitTask.value.get() }

        let task = Task(name: "Beam.TokenAuth.wait") { () -> Result<Token, AuthError> in
            defer { waitTask = nil }
            await withCheckedContinuation { initContinuation = $0 }
            if Task.isCancelled { return .failure(.cancelled) }
            do throws(AuthError) {
                return .success(try await resolveToken())
            } catch {
                return .failure(error)
            }
        }

        waitTask = task
        return try await task.value.get()
    }

    // MARK: - Helpers

    private func resumeInit() {
        initContinuation?.resume()
        initContinuation = nil
    }
}

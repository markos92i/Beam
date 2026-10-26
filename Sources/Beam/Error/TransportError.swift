//
//  TransportError.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 11/3/25.
//

import Foundation

/// Failures of the HTTP transport (`Client`): URLSession's own, or of files it handles itself.
public enum TransportError: Error, LoggableError {
    case network(URLError)
    /// A file the transport needs could not be read, written or kept.
    case file(FileError)

    /// The `URLError` behind a network failure.
    public var urlError: URLError? {
        if case .network(let error) = self { error } else { nil }
    }

    var logDescription: String {
        switch self {
        case .network(let error): error.logDescription
        case .file(let error): error.logDescription
        }
    }
}

// MARK: - URLError

extension URLError {
    /// URLSession's async APIs are untyped but document `URLError`; anything else becomes `.unknown`.
    init(bridging error: any Error) {
        switch error {
        case let error as URLError: self = error
        case is CancellationError: self.init(.cancelled)
        default: self.init(.unknown, userInfo: [NSUnderlyingErrorKey: error])
        }
    }

    /// Shared by HTTP retries and WebSocket reconnection.
    var isTransient: Bool {
        switch code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet: true
        default: false
        }
    }

    /// Failed before anything left the device, so the server can't have applied it.
    var wasNeverSent: Bool { code == .notConnectedToInternet }

    var logDescription: String { localizedDescription }
}

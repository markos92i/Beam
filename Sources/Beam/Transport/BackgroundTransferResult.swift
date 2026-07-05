//
//  BackgroundTransferResult.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 3/7/26.
//

import Foundation

/// Result of a background transfer completed while the app was suspended or terminated.
///
/// When the app is relaunched for background session events, per-task closures
/// no longer exist. `BackgroundTransferResult` captures the raw outcome so the
/// app can process it manually.
public struct BackgroundTransferResult: Sendable {
    /// The original request URL, if available.
    public let originalURL: URL?

    /// The task description set before the transfer started (useful for identifying what was requested).
    public let taskDescription: String?

    /// The HTTP status code of the response, if available.
    public let statusCode: Int?

    /// The transfer outcome.
    public let outcome: Outcome

    /// Possible outcomes for a background transfer.
    public enum Outcome: Sendable {
        /// Download completed. The file has been copied to a stable temporary location.
        case downloaded(URL)

        /// Upload completed with the server's response data.
        case uploaded(Data)

        /// Transfer failed.
        case failed(TransportError)
    }
}

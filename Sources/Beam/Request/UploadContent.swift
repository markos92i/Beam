//
//  UploadContent.swift
//  Beam
//
//  What an upload sends.
//

import Foundation

/// What an upload sends. Kept out of the request, so interceptors and auth don't see it.
public enum UploadContent: Sendable {
    /// Encoded and uploaded from memory; its content type goes in the request's headers.
    case body(HTTPBody)
    /// Streamed from disk. Set its `Content-Type` in the request's headers if needed.
    case file(URL)

    var contentType: ContentType? {
        if case .body(let body) = self { body.contentType } else { nil }
    }
}

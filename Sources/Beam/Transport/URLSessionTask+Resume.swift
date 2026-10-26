//
//  URLSessionTask+Resume.swift
//  Beam
//
//  Upload tasks made from resume data URLSession can't read.
//

import Foundation

extension URLSessionTask {
    /// Read via KVC: an upload task from unreadable resume data has no `progress`, and Swift crashes reading it.
    var progressIfAny: Progress? {
        value(forKey: #keyPath(URLSessionTask.progress)) as? Progress
    }
}

extension URLError {
    /// The error URLSession itself gives a download resumed from unreadable resume data.
    static var unreadableResumeData: URLError { URLError(.unsupportedURL) }
}

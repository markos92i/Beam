//
//  BackgroundTransferResult.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 3/7/26.
//

import Foundation

struct BackgroundTransferResult: Sendable {
    let request: URLRequest?

    let taskDescription: String?

    let response: HTTPURLResponse?

    var outcome: Outcome

    var storeID: String? = nil

    enum Outcome: Sendable {
        case downloaded(URL)
        case uploaded(Data)
        case failed(TransportError)

        init(keeping file: Result<URL, TransportError>) {
            switch file {
            case .success(let url): self = .downloaded(url)
            case .failure(let error): self = .failed(error)
            }
        }
    }
}

extension BackgroundTransferResult {
    init(task: URLSessionTask, outcome: Outcome, storeID: String? = nil) {
        self.init(
            request: task.originalRequest,
            taskDescription: task.taskDescription,
            response: task.response as? HTTPURLResponse,
            outcome: outcome,
            storeID: storeID
        )
    }
}

// MARK: - As an attempt's response

extension BackgroundTransferResult {
    func uploadResponse() throws(TransportError) -> (Data, URLResponse) {
        switch outcome {
        case .uploaded(let data):
            guard let response else { throw .network(URLError(.badServerResponse)) }
            return (data, response)
        case .failed(let error):
            throw error
        case .downloaded:
            throw .network(URLError(.badServerResponse))
        }
    }

    func downloadResponse() throws(TransportError) -> (URL, URLResponse) {
        switch outcome {
        case .downloaded(let url):
            guard let response else { throw .network(URLError(.badServerResponse)) }
            return (url, response)
        case .failed(let error):
            throw error
        case .uploaded:
            throw .network(URLError(.badServerResponse))
        }
    }
}

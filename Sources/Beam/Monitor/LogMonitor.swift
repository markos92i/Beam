//
//  LogMonitor.swift
//  Beam
//

import Foundation

struct LogMonitor: Monitor {
    let log: BeamLogger
    let maxAttempts: Int

    func willRetry(after error: APIError<Void>, delay: Duration, context: EndpointContext) {
        let attempt = context.attempt + 1
        log.log(context.operation == .connection
            ? .wsReconnect(id: context.id, attempt: attempt, max: maxAttempts, delay: delay)
            : .retry(id: context.id, attempt: attempt, max: maxAttempts, delay: delay))
    }

    func didFail(_ failure: EndpointFailure, context: EndpointContext) {
        let error = failure.error
        log.log(.error(id: context.id, icon: error.icon, name: error.name, detail: error.logDescription, attempt: context.attempt))
    }
}

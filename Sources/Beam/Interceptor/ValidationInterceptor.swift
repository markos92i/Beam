//
//  ValidationInterceptor.swift
//  Beam
//

import Foundation

/// Keeps the raw body so it can be decoded into the route's `Failure`.
struct ValidationInterceptor: Interceptor {
    func intercept(response: Response, context: EndpointContext) async throws(InterceptorError) -> Response {
        guard response.status.succeeds(for: context.operation) else {
            throw .rejected(status: response.status, body: response.errorBody)
        }
        return response
    }
}

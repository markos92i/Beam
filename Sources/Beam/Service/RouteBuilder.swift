//
//  RouteBuilder.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import Foundation

/// Builds a `Service` from a parent `_APIConfiguration` plus route-specific parameters.
/// Used by the code generated from `@Route` macro.
public func _buildRoute<Success: Sendable, Failure: Sendable>(
    config: _APIConfiguration,
    method: HTTPMethod,
    path: String,
    body: HTTPBody? = nil,
    extraHeaders: [String: String] = [:],
    extraComponents: [RequestComponent] = [],
    queryItems: [URLQueryItem] = [],
    authPolicy: AuthPolicy = .required
) -> Service<Success, Failure> {
    // Start with a fresh builder state
    var state = RequestBuilderState()

    // Apply group-level components first
    for component in config.components {
        component.apply(to: &state)
    }

    // Apply extra components (route-level overrides)
    for component in extraComponents {
        component.apply(to: &state)
    }

    // Set the method and path from route
    state.method = method
    state.host = config.host
    state.path = config.base + path

    // Merge extra headers
    state.headers.merge(extraHeaders) { _, new in new }

    // Append query items
    state.params.append(contentsOf: queryItems)

    // Set body if provided
    if let body {
        state.body = body
    }

    let api = APIRequest(
        method: state.method,
        host: state.host,
        path: state.path,
        params: state.params,
        headers: state.headers,
        body: state.body,
        cacheFile: state.cacheFile
    )

    return Service<Success, Failure>(
        client: state.client,
        auth: state.auth,
        crash: state.crash,
        serializer: state.serializer,
        config: state.config,
        authPolicy: authPolicy,
        api: api
    )
}

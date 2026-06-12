//
//  DSLBuilder.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 01/06/2026.
//

import Foundation

@resultBuilder
public struct DSLBuilder {
    public static func buildExpression(_ expression: RequestComponent) -> [RequestComponent] { [expression] }
    public static func buildBlock(_ components: [RequestComponent]...) -> [RequestComponent] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [RequestComponent]?) -> [RequestComponent] { component ?? [] }
    public static func buildEither(first component: [RequestComponent]) -> [RequestComponent] { component }
    public static func buildEither(second component: [RequestComponent]) -> [RequestComponent] { component }
    public static func buildArray(_ components: [[RequestComponent]]) -> [RequestComponent] { components.flatMap { $0 } }
    
    public static func buildFinalResult<Success, Failure>(_ components: [RequestComponent]) -> DataTask<Success, Failure> {
        DataTask(service: buildService(from: components))
    }

    public static func buildFinalResult<Success, Failure>(_ components: [RequestComponent]) -> UploadTask<Success, Failure> {
        UploadTask(service: buildService(from: components))
    }

    public static func buildFinalResult<Failure>(_ components: [RequestComponent]) -> DownloadTask<Failure> {
        DownloadTask(service: buildService(from: components))
    }
    
    public static func buildFinalResult(_ components: [RequestComponent]) -> [RequestComponent] { components }
    
    private static func buildService<Success, Failure>(from components: [RequestComponent]) -> Service<Success, Failure> {
        var state = RequestBuilderState()
        components.forEach { $0.apply(to: &state) }
        
        let payload = ServicePayload(
            method: state.method,
            host: state.host,
            path: state.path,
            params: state.params,
            headers: state.headers,
            body: state.body,
            timeout: state.timeout,
            cacheFile: state.cacheFile
        )
        
        return Service<Success, Failure>(
            client: state.client,
            auth: state.auth,
            crash: state.crash,
            serializer: state.serializer,
            config: state.config,
            api: payload
        )
    }
}

// MARK: - Core Protocol
public protocol RequestComponent {
    func apply(to builder: inout RequestBuilderState)
}

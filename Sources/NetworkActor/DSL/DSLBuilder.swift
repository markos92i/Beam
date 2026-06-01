//
//  DSLBuilder.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 01/06/2026.
//

import Foundation

@resultBuilder
public struct DSLBuilder {
    public static func buildExpression(_ expr: DSL.Method<BodyForbidden>) -> DSL.Method<BodyForbidden> { expr }
    public static func buildExpression(_ expr: DSL.Method<BodyAllowed>) -> DSL.Method<BodyAllowed> { expr }
    public static func buildExpression<C: SafeComponent>(_ expr: C) -> ComponentWrapper<BodyForbidden> { .init(expr) }
    public static func buildExpression(_ expr: DSL.Body) -> ComponentWrapper<BodyAllowed> { .init(expr) }
    public static func buildOptional(_ component: ComponentWrapper<BodyForbidden>?) -> ComponentWrapper<BodyForbidden> { .init(component?.component ?? EmptyComponent()) }
    
    public static func buildOptional(_ component: ComponentWrapper<BodyAllowed>?) -> ComponentWrapper<BodyAllowed> { .init(component?.component ?? EmptyComponent()) }
    
    public static func buildEither(first component: ComponentWrapper<BodyForbidden>) -> ComponentWrapper<BodyForbidden> { component }
    public static func buildEither(second component: ComponentWrapper<BodyForbidden>) -> ComponentWrapper<BodyForbidden> { component }
    
    public static func buildEither(first component: ComponentWrapper<BodyAllowed>) -> ComponentWrapper<BodyAllowed> { component }
    public static func buildEither(second component: ComponentWrapper<BodyAllowed>) -> ComponentWrapper<BodyAllowed> { component }
    
    public static func buildEither(first component: ComponentWrapper<BodyForbidden>) -> ComponentWrapper<BodyAllowed> { .init(component.component) }
    public static func buildEither(second component: ComponentWrapper<BodyForbidden>) -> ComponentWrapper<BodyAllowed> { .init(component.component) }
    
    public static func buildBlock(_ components: ComponentWrapper<BodyForbidden>...) -> ComponentWrapper<BodyForbidden> {
        ComponentWrapper(CombinedComponent(components.map { $0.component }))
    }
    
    public static func buildBlock<each C: AnyComponentWrapper>(_ components: repeat each C) -> ComponentWrapper<BodyAllowed> {
        var array: [any RequestComponent] = []
        repeat array.append((each components).erasedComponent)
        return ComponentWrapper(CombinedComponent(array))
    }
    
    public static func buildBlock(_ m: DSL.Method<BodyForbidden>, _ components: ComponentWrapper<BodyForbidden>...) -> [any RequestComponent] {
        var result: [any RequestComponent] = [m]
        result.append(contentsOf: components.map { $0.component })
        return result
    }
    
    public static func buildBlock<each C: AnyComponentWrapper>(_ m: DSL.Method<BodyAllowed>, _ components: repeat each C) -> [any RequestComponent] {
        var result: [any RequestComponent] = [m]
        repeat result.append((each components).erasedComponent)
        return result
    }

    public static func buildFinalResult<Success: Sendable, Failure: Sendable>(_ components: [any RequestComponent]) -> Service<Success, Failure> {
        var state = RequestBuilderState()
        components.forEach { $0.apply(to: &state) }
        
        let payload = ServicePayload(
            method: state.method,
            host: state.host,
            path: state.path,
            params: state.params,
            headers: state.headers,
            body: state.body,
            timeout: state.timeout
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

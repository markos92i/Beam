//
//  RequestComponent.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 01/06/2026.
//

import Foundation

public enum BodyForbidden {}
public enum BodyAllowed {}

public protocol RequestComponent {
    func apply(to builder: inout RequestBuilderState)
}

public protocol SafeComponent: RequestComponent {}

public protocol AnyComponentWrapper {
    var erasedComponent: any RequestComponent { get }
}

public struct ComponentWrapper<Safety>: AnyComponentWrapper {
    public let component: any RequestComponent
    public var erasedComponent: any RequestComponent { component }
    
    public init(_ component: any RequestComponent) { self.component = component }
}

struct CombinedComponent: RequestComponent {
    let components: [any RequestComponent]
    
    public init(_ components: [any RequestComponent]) { self.components = components }

    func apply(to builder: inout RequestBuilderState) { components.forEach { $0.apply(to: &builder) } }
}

struct EmptyComponent: RequestComponent {
    func apply(to builder: inout RequestBuilderState) {}
}

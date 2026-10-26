//
//  Endpoint+Formats.swift
//  Beam
//
//  How an endpoint reads its bodies, chosen from its types, as `@API` does.
//
//  A type is read in one of three ways — `Decodable` (text for `String`, the raw bytes
//  for `Data`, JSON otherwise), `Void` (no body) or `BodyRepresentable` (its own) — so
//  there is one initializer per pair of ways, response and error: nine, whatever types
//  Beam supports. A new type adds a conformance, not initializers.
//

import Foundation

extension Endpoint where Success: Decodable & SendableMetatype, Failure: Decodable & SendableMetatype {
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        self.init(api, config: config, request: request, response: .automatic, error: .automatic)
    }
}

extension Endpoint where Success: Decodable & SendableMetatype, Failure == Void {
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        self.init(api, config: config, request: request, response: .automatic, error: .void)
    }
}

extension Endpoint where Success: Decodable & SendableMetatype, Failure: BodyRepresentable {
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        self.init(api, config: config, request: request, response: .automatic, error: .representable)
    }
}

extension Endpoint where Success == Void, Failure: Decodable & SendableMetatype {
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        self.init(api, config: config, request: request, response: .void, error: .automatic)
    }
}

extension Endpoint where Success == Void, Failure == Void {
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        self.init(api, config: config, request: request, response: .void, error: .void)
    }
}

extension Endpoint where Success == Void, Failure: BodyRepresentable {
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        self.init(api, config: config, request: request, response: .void, error: .representable)
    }
}

extension Endpoint where Success: BodyRepresentable, Failure: Decodable & SendableMetatype {
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        self.init(api, config: config, request: request, response: .representable, error: .automatic)
    }
}

extension Endpoint where Success: BodyRepresentable, Failure == Void {
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        self.init(api, config: config, request: request, response: .representable, error: .void)
    }
}

extension Endpoint where Success: BodyRepresentable, Failure: BodyRepresentable {
    public init(_ api: APIConfiguration, config: RequestConfig? = nil, request: APIRequest) {
        self.init(api, config: config, request: request, response: .representable, error: .representable)
    }
}

//
//  RouteParameters.swift
//  Beam
//
//  Request-building helpers called by `@API`-generated code.
//
//  The macro only sees syntax, so it decides a parameter's role from its label
//  (`body`, `query`, `header`, `url`, `{name}` in the path) and leaves the
//  type-dependent part to these overloads. The compiler picks the overload with
//  full type information, so typealiases, `Optional<T>`, `T!`, raw-value enums and
//  module-qualified names all work, and an unsupported shape fails to compile with
//  an explicit message instead of being sent wrong or dropped silently.
//

import Foundation

/// Used by @API.
public enum _Route {

    // MARK: - Placeholder values

    /// The value of a `{name}` placeholder.
    public enum Value: Sendable, Equatable {
        case value(String)
        /// A `nil` optional parameter: its query item is omitted.
        case omitted
        /// A `nil` ``APIValues`` property: the request fails with ``APIError/missingValue(_:)``.
        case missing(String)
    }

    // MARK: Path placeholder filled by a parameter

    /// A `{name}` path segment.
    public static func path(_ value: some HTTPParameterValue) -> Value {
        .value(value.httpParameterValue)
    }

    public static func path<T: RawRepresentable>(_ value: T) -> Value where T.RawValue: HTTPParameterValue {
        .value(value.rawValue.httpParameterValue)
    }

    /// Disambiguates raw-value enums that also conform to `HTTPParameterValue`.
    public static func path<T: RawRepresentable & HTTPParameterValue>(_ value: T) -> Value where T.RawValue: HTTPParameterValue {
        .value(value.rawValue.httpParameterValue)
    }

    @available(*, unavailable, message: "Path parameters can't be optional: a missing value would produce a different URL")
    public static func path<T>(_ value: T?) -> Value { fatalError() }

    @available(*, unavailable, message: "Path parameters can't be arrays")
    public static func path<T>(_ value: [T]) -> Value { fatalError() }

    @available(*, unavailable, message: "Unsupported path parameter type: conform it to HTTPParameterValue, or use a raw-value enum")
    public static func path<T>(_ value: T) -> Value { fatalError() }

    // MARK: Query placeholder filled by a parameter

    /// A `{name}` value in a route's `query:`.
    public static func queryValue(_ value: some HTTPParameterValue) -> Value {
        .value(value.httpParameterValue)
    }

    public static func queryValue<T: RawRepresentable>(_ value: T) -> Value where T.RawValue: HTTPParameterValue {
        .value(value.rawValue.httpParameterValue)
    }

    public static func queryValue<T: RawRepresentable & HTTPParameterValue>(_ value: T) -> Value where T.RawValue: HTTPParameterValue {
        .value(value.rawValue.httpParameterValue)
    }

    public static func queryValue(_ value: (some HTTPParameterValue)?) -> Value {
        value.map { queryValue($0) } ?? .omitted
    }

    public static func queryValue<T: RawRepresentable>(_ value: T?) -> Value where T.RawValue: HTTPParameterValue {
        value.map { queryValue($0) } ?? .omitted
    }

    public static func queryValue<T: RawRepresentable & HTTPParameterValue>(_ value: T?) -> Value where T.RawValue: HTTPParameterValue {
        value.map { queryValue($0) } ?? .omitted
    }

    @available(*, unavailable, message: "Arrays in a query value need an explicit format (repeated key or comma-separated); format the value explicitly")
    public static func queryValue<T>(_ values: [T]) -> Value { fatalError() }

    @available(*, unavailable, message: "Unsupported query value type: conform it to HTTPParameterValue, or use a raw-value enum")
    public static func queryValue<T>(_ value: T) -> Value { fatalError() }

    // MARK: Placeholder filled by APIValues

    /// The ``APIValues`` property `name`, used by a `{name}` placeholder.
    public static func shared(_ name: String, _ value: some HTTPParameterValue) -> Value {
        .value(value.httpParameterValue)
    }

    public static func shared<T: RawRepresentable>(_ name: String, _ value: T) -> Value where T.RawValue: HTTPParameterValue {
        .value(value.rawValue.httpParameterValue)
    }

    public static func shared<T: RawRepresentable & HTTPParameterValue>(_ name: String, _ value: T) -> Value where T.RawValue: HTTPParameterValue {
        .value(value.rawValue.httpParameterValue)
    }

    public static func shared(_ name: String, _ value: (some HTTPParameterValue)?) -> Value {
        value.map { shared(name, $0) } ?? .missing(name)
    }

    public static func shared<T: RawRepresentable>(_ name: String, _ value: T?) -> Value where T.RawValue: HTTPParameterValue {
        value.map { shared(name, $0) } ?? .missing(name)
    }

    public static func shared<T: RawRepresentable & HTTPParameterValue>(_ name: String, _ value: T?) -> Value where T.RawValue: HTTPParameterValue {
        value.map { shared(name, $0) } ?? .missing(name)
    }

    @available(*, unavailable, message: "APIValues used in placeholders can't be arrays")
    public static func shared<T>(_ name: String, _ values: [T]) -> Value { fatalError() }

    @available(*, unavailable, message: "Unsupported APIValues type: conform it to HTTPParameterValue, or use a raw-value enum")
    public static func shared<T>(_ name: String, _ value: T) -> Value { fatalError() }

    // MARK: - Named query (`query name: T`)

    public static func query(_ name: String, _ value: some HTTPParameterValue) -> [URLQueryItem] {
        [URLQueryItem(name: name, value: value.httpParameterValue)]
    }

    public static func query<T: RawRepresentable>(_ name: String, _ value: T) -> [URLQueryItem] where T.RawValue: HTTPParameterValue {
        [URLQueryItem(name: name, value: value.rawValue.httpParameterValue)]
    }

    public static func query<T: RawRepresentable & HTTPParameterValue>(_ name: String, _ value: T) -> [URLQueryItem] where T.RawValue: HTTPParameterValue {
        [URLQueryItem(name: name, value: value.rawValue.httpParameterValue)]
    }

    public static func query(_ name: String, _ value: (some HTTPParameterValue)?) -> [URLQueryItem] {
        value.map { query(name, $0) } ?? []
    }

    public static func query<T: RawRepresentable>(_ name: String, _ value: T?) -> [URLQueryItem] where T.RawValue: HTTPParameterValue {
        value.map { query(name, $0) } ?? []
    }

    public static func query<T: RawRepresentable & HTTPParameterValue>(_ name: String, _ value: T?) -> [URLQueryItem] where T.RawValue: HTTPParameterValue {
        value.map { query(name, $0) } ?? []
    }

    public static func query(_ name: String, _ items: [URLQueryItem]) -> [URLQueryItem] {
        items
    }

    public static func query(_ name: String, _ items: [URLQueryItem]?) -> [URLQueryItem] {
        items ?? []
    }

    /// Repeats the key per value (`id=1&id=2`); pass `[URLQueryItem]` for another format.
    public static func query(_ name: String, _ values: [some HTTPParameterValue]) -> [URLQueryItem] {
        values.flatMap { query(name, $0) }
    }

    public static func query<T: RawRepresentable>(_ name: String, _ values: [T]) -> [URLQueryItem] where T.RawValue: HTTPParameterValue {
        values.flatMap { query(name, $0) }
    }

    public static func query<T: RawRepresentable & HTTPParameterValue>(_ name: String, _ values: [T]) -> [URLQueryItem] where T.RawValue: HTTPParameterValue {
        values.flatMap { query(name, $0) }
    }

    public static func query(_ name: String, _ values: [some HTTPParameterValue]?) -> [URLQueryItem] {
        values.map { query(name, $0) } ?? []
    }

    public static func query<T: RawRepresentable>(_ name: String, _ values: [T]?) -> [URLQueryItem] where T.RawValue: HTTPParameterValue {
        values.map { query(name, $0) } ?? []
    }

    public static func query<T: RawRepresentable & HTTPParameterValue>(_ name: String, _ values: [T]?) -> [URLQueryItem] where T.RawValue: HTTPParameterValue {
        values.map { query(name, $0) } ?? []
    }

    @available(*, unavailable, message: "Unsupported query array element: conform it to HTTPParameterValue, or use a raw-value enum")
    public static func query<T>(_ name: String, _ values: [T]) -> [URLQueryItem] { fatalError() }

    @available(*, unavailable, message: "Unsupported query array element: conform it to HTTPParameterValue, or use a raw-value enum")
    public static func query<T>(_ name: String, _ values: [T]?) -> [URLQueryItem] { fatalError() }

    @available(*, unavailable, message: "Dictionaries can't be a named query value; pass [URLQueryItem] instead")
    public static func query<K, V>(_ name: String, _ values: [K: V]) -> [URLQueryItem] { fatalError() }

    @available(*, unavailable, message: "Unsupported query value type: conform it to HTTPParameterValue, or use a raw-value enum")
    public static func query<T>(_ name: String, _ value: T) -> [URLQueryItem] { fatalError() }

    // MARK: - Unlabeled parameters

    @available(*, unavailable, message: "This parameter has no role, so it would not be sent: label it `query name`, `header name` or `body`, name it after a {placeholder}, or pass [URLQueryItem]")
    public static func queryItems<T>(_ value: T) -> [URLQueryItem] { fatalError() }

    public static func queryItems(_ items: [URLQueryItem]) -> [URLQueryItem] {
        items
    }

    public static func queryItems(_ items: [URLQueryItem]?) -> [URLQueryItem] {
        items ?? []
    }

    // MARK: - Headers (`header name: T`)

    public static func header(_ name: String, _ value: some HTTPParameterValue) -> [String: String] {
        [name: value.httpParameterValue]
    }

    public static func header<T: RawRepresentable>(_ name: String, _ value: T) -> [String: String] where T.RawValue: HTTPParameterValue {
        [name: value.rawValue.httpParameterValue]
    }

    public static func header<T: RawRepresentable & HTTPParameterValue>(_ name: String, _ value: T) -> [String: String] where T.RawValue: HTTPParameterValue {
        [name: value.rawValue.httpParameterValue]
    }

    public static func header(_ name: String, _ value: (some HTTPParameterValue)?) -> [String: String] {
        value.map { header(name, $0) } ?? [:]
    }

    public static func header<T: RawRepresentable>(_ name: String, _ value: T?) -> [String: String] where T.RawValue: HTTPParameterValue {
        value.map { header(name, $0) } ?? [:]
    }

    public static func header<T: RawRepresentable & HTTPParameterValue>(_ name: String, _ value: T?) -> [String: String] where T.RawValue: HTTPParameterValue {
        value.map { header(name, $0) } ?? [:]
    }

    @available(*, unavailable, message: "Header values can't be arrays")
    public static func header<T>(_ name: String, _ values: [T]) -> [String: String] { fatalError() }

    @available(*, unavailable, message: "Unsupported header value type: conform it to HTTPParameterValue, or use a raw-value enum")
    public static func header<T>(_ name: String, _ value: T) -> [String: String] { fatalError() }

    /// Merges header layers in order; later layers win on conflicts.
    public static func headers(_ layers: [String: String]...) -> [String: String] {
        layers.reduce(into: [:]) { merged, layer in
            merged.merge(layer) { _, new in new }
        }
    }

    // MARK: - Body (`body: T`)

    public static func body(_ body: HTTPBody) -> HTTPBody? {
        body
    }

    public static func body(_ body: HTTPBody?) -> HTTPBody? {
        body
    }

    /// Sent as is (`application/octet-stream`), not as JSON.
    public static func body(_ data: Data) -> HTTPBody? {
        .data(data)
    }

    public static func body(_ data: Data?) -> HTTPBody? {
        data.map { .data($0) }
    }

    /// Sent as UTF-8 `text/plain`, not as a JSON string.
    public static func body(_ text: String) -> HTTPBody? {
        .data(Data(text.utf8), contentType: .text)
    }

    public static func body(_ text: String?) -> HTTPBody? {
        text.map { .data(Data($0.utf8), contentType: .text) }
    }

    public static func body(_ value: some Encodable & Sendable) -> HTTPBody? {
        .json(value)
    }

    /// `nil` sends no body, not JSON `null`.
    public static func body(_ value: (some Encodable & Sendable)?) -> HTTPBody? {
        value.map { .json($0) }
    }

    @available(*, unavailable, message: "A `body` parameter must be Encodable & Sendable, or an HTTPBody")
    public static func body<T>(_ value: T) -> HTTPBody? { fatalError() }

    // MARK: - Upload content (`body: T` or `url: URL` in `task: .upload`)

    public static func uploadBody(_ body: HTTPBody) -> UploadContent {
        .body(body)
    }

    public static func uploadBody(_ data: Data) -> UploadContent {
        .body(.data(data))
    }

    public static func uploadBody(_ text: String) -> UploadContent {
        .body(.data(Data(text.utf8), contentType: .text))
    }

    public static func uploadBody(_ value: some Encodable & Sendable) -> UploadContent {
        .body(.json(value))
    }

    // Deprecated, not unavailable: that would lose to the Encodable overload; the return type breaks compilation.
    @available(*, deprecated, message: "An upload route's `body` can't be optional: an upload without content has nothing to send. Make it non-optional, or declare a data route (`task: .data`) for the call without it")
    public static func uploadBody(_ value: (some Encodable & Sendable)?) -> _UploadBodyMustNotBeOptional { fatalError() }

    @available(*, unavailable, message: "An upload route's `body` can't be optional: an upload without content has nothing to send. Make it non-optional, or declare a data route (`task: .data`) for the call without it")
    public static func uploadBody<T>(_ value: T?) -> UploadContent { fatalError() }

    @available(*, unavailable, message: "A `body` parameter must be Encodable & Sendable, or an HTTPBody")
    public static func uploadBody<T>(_ value: T) -> UploadContent { fatalError() }

    // MARK: - URLs (`url: URL`)

    /// Replaces the API's host, base and route path.
    public static func absoluteURL(_ url: URL) -> URL {
        url
    }

    @available(*, unavailable, message: "A `url` parameter is the absolute request URL and must be a non-optional URL; use another label for other values")
    public static func absoluteURL<T>(_ value: T) -> URL { fatalError() }

    public static func uploadFile(_ url: URL) -> URL {
        url
    }

    @available(*, unavailable, message: "In an upload route, `url` is the local file to upload and must be a non-optional URL")
    public static func uploadFile<T>(_ value: T) -> URL { fatalError() }

    // MARK: - Resume data (`resumeFrom: Data`)

    public static func resumeData(_ data: Data) -> Data {
        data
    }

    @available(*, unavailable, message: "`resumeFrom` is the resume data of a cancelled transfer and must be a non-optional Data")
    public static func resumeData<T>(_ value: T) -> Data { fatalError() }

    // MARK: - Background

    /// Only called when `@API(background:)` is set.
    public static func background(_ configuration: APIConfiguration) -> Session<Background> {
        guard let session = configuration.background else {
            preconditionFailure("@API has no background session")
        }
        return session
    }
}

/// Used by @API to reject an optional upload `body`.
public enum _UploadBodyMustNotBeOptional {}

extension APIError {
    /// Used by @API to read the failure type through typealiases.
    public typealias _Failure = Failure
}

// MARK: - Parameter values

/// A value sendable as a path segment, query value or header value.
/// Raw-value enums work without conforming; `Date` doesn't conform, its format depends on the API.
public protocol HTTPParameterValue {
    /// The textual form sent over HTTP.
    var httpParameterValue: String { get }
}

extension String: HTTPParameterValue { public var httpParameterValue: String { self } }
extension Substring: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension Bool: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension Int: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension Int8: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension Int16: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension Int32: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension Int64: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension UInt: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension UInt8: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension UInt16: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension UInt32: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension UInt64: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension Double: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension Float: HTTPParameterValue { public var httpParameterValue: String { String(self) } }
extension Decimal: HTTPParameterValue { public var httpParameterValue: String { "\(self)" } }
extension UUID: HTTPParameterValue { public var httpParameterValue: String { uuidString } }

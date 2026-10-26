//
//  APIMacro.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Expands `@API` into `<Protocol>Client`.
public struct APIMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            throw MacroError("@API can only be applied to protocols")
        }

        var arguments: [String: String] = [:]
        for argument in node.arguments?.as(LabeledExprListSyntax.self) ?? [] {
            if let label = argument.label?.text { arguments[label] = argument.expression.trimmedDescription }
        }
        guard let host = arguments["host"] else {
            throw MacroError("@API requires 'host' parameter")
        }

        let protocolName = protocolDecl.name.text
        var functions: [FunctionInfo] = []
        for member in protocolDecl.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self),
                  let route = parseRoute(of: funcDecl, in: context) else { continue }
            let function = parseFunctionSignature(funcDecl, route: route)
            diagnoseContent(of: function, declaredBy: funcDecl, in: context)
            functions.append(function)
        }
        assignMockNames(&functions)
        diagnoseUnusedServices(arguments, of: functions, attribute: node, in: context)

        var output = """
        // @unchecked Sendable: mock closures are nil in production and thread-safe by design.
        // Assigning mock closures concurrently with active calls is a caller error.
        struct \(protocolName)Client: \(protocolName), @unchecked Sendable {
            static let _apiConfiguration = Beam::APIConfiguration(
                host: \(host),
                base: \(arguments["base"] ?? "\"\""),
                headers: \(arguments["headers"] ?? "[:]")
        """
        // Labels must follow `APIConfiguration.init`'s parameter order.
        for label in ["session", "background", "auth", "monitors", "config", "socket", "interceptors", "logLevel"] {
            if let value = arguments[label] { output += ",\n            \(label): \(value)" }
        }
        output += """

            )

            private let _config: Beam::APIConfiguration

            init(session: (any Beam::SessionProtocol)? = nil) {
                _config = Self._apiConfiguration.replacing(session: session)
            }

        """
        output += generateMockProperties(functions: functions)
        output += "\n"
        for function in functions {
            output += generateFunction(function, in: protocolName, background: arguments["background"] != nil)
            output += "\n"
        }
        output += "}"

        return [DeclSyntax(stringLiteral: output)]
    }

    // MARK: - Routes

    private static let routeMethods = [
        "Get": "get", "Post": "post", "Put": "put", "Delete": "delete", "Patch": "patch",
        "Head": "head", "Options": "options", "Trace": "trace", "Socket": "get",
    ]

    private static func parseRoute(of funcDecl: FunctionDeclSyntax, in context: some MacroExpansionContext) -> RouteInfo? {
        for attr in funcDecl.attributes {
            // `@Get`, `@Beam.Get` and `@Beam::Get`; another module's `@Get` is not ours.
            guard let attribute = attr.as(AttributeSyntax.self),
                  let name = attribute.attributeName.nominalName(inModule: "Beam"),
                  let method = routeMethods[name] else { continue }

            let argList = attribute.arguments?.as(LabeledExprListSyntax.self).map(Array.init) ?? []
            let pathExpr = argList.first.flatMap { $0.label == nil ? $0.expression : nil }
            let path = parseRoutePath(pathExpr, in: context)
            var route = RouteInfo(
                method: method,
                path: path.literal,
                pathPlaceholders: placeholders(in: path.content, of: pathExpr, attribute: attribute, context: context),
                taskKind: name == "Socket" ? "stream" : "data"
            )

            for arg in pathExpr == nil ? argList[...] : argList.dropFirst() {
                switch arg.label?.text {
                case "task":
                    // A variable or call type-checks but can't be read at expansion time.
                    if let member = arg.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text {
                        route.taskKind = member
                    } else {
                        context.diagnose(Diagnostic(node: arg.expression, message: MacroDiagnostic.taskNotLiteral))
                    }
                case "query":
                    route.routeQuery = parseRouteQuery(arg.expression, in: context)
                case let label?:
                    let value = arg.expression.trimmedDescription
                    if value != "nil" { route.options[label] = value }
                case nil:
                    break
                }
            }
            return route
        }
        return nil
    }

    private static func parseFunctionSignature(_ funcDecl: FunctionDeclSyntax, route: RouteInfo) -> FunctionInfo {
        let placeholderNames = Set(route.pathPlaceholders + route.routeQuery.compactMap(\.placeholder))

        // Roles come from labels only; type-dependent handling is left to `_Route` overloads.
        let params = funcDecl.signature.parameterClause.parameters.map { param in
            let externalName = param.firstName.text
            let internalName = param.secondName?.text ?? externalName

            let role: ParamRole
            if externalName == "body" {
                role = .body
            } else if externalName == "query" {
                role = .queryNamed(key: internalName)
            } else if externalName == "header" {
                role = .header(key: internalName)
            } else if placeholderNames.contains(externalName) || placeholderNames.contains(internalName) {
                role = .placeholder
            } else if externalName == "url" {
                role = route.taskKind == "upload" ? .uploadFile : .absoluteURL
            } else if externalName == "resumeFrom", ["upload", "download"].contains(route.taskKind) {
                role = .resumeData
            } else {
                role = .unlabeled
            }
            return ParamInfo(externalName: externalName == "_" ? nil : externalName, internalName: internalName, syntax: param, role: role)
        }

        return FunctionInfo(
            name: funcDecl.name.text,
            params: params,
            returnType: funcDecl.signature.returnClause?.type.trimmedDescription,
            // Used as written; its failure type is read through `APIError._Failure`.
            errorType: funcDecl.signature.effectSpecifiers?.throwsClause?.type?.trimmedDescription ?? "APIError<Void>",
            route: route
        )
    }

    private static func diagnoseContent(of fn: FunctionInfo, declaredBy funcDecl: FunctionDeclSyntax, in context: some MacroExpansionContext) {
        func diagnose(_ node: some SyntaxProtocol, _ message: MacroDiagnostic) {
            context.diagnose(Diagnostic(node: node, message: message))
        }
        let body = fn.params.first { $0.role == .body }
        let file = fn.params.first { $0.role == .uploadFile }
        let contentless = ContentlessMethod(rawValue: fn.route.method)

        switch fn.route.taskKind {
        case "stream":
            for param in fn.params {
                if param.role == .body { diagnose(param.syntax, .socketBody) }
                if param.role == .absoluteURL { diagnose(param.syntax, .socketURL) }
            }
            if let ping = fn.route.options["ping"], let seconds = literalSeconds(ping), !(1...300).contains(seconds) {
                diagnose(funcDecl.name, .pingOutOfRange(ping))
            }
            if let size = fn.route.options["maxMessageSize"].flatMap({ Int($0.replacingOccurrences(of: "_", with: "")) }), size <= 0 {
                diagnose(funcDecl.name, .invalidMessageSize)
            }
        case "upload":
            if let contentless { diagnose(funcDecl.name, .contentNotAllowed(contentless)) }
            if let body, file != nil { diagnose(body.syntax, .bodyWithFile) }
            if body == nil, file == nil { diagnose(funcDecl.name, .uploadWithoutContent) }
        default:
            if let contentless, let body { diagnose(body.syntax, .contentNotAllowed(contentless)) }
        }
    }

    /// The seconds of a `.seconds(n)` or `.milliseconds(n)` literal.
    private static func literalSeconds(_ duration: String) -> Double? {
        let units: [(String, Double)] = [(".seconds(", 1), (".milliseconds(", 0.001)]
        for (prefix, scale) in units where duration.hasPrefix(prefix) && duration.hasSuffix(")") {
            let number = duration.dropFirst(prefix.count).dropLast().replacingOccurrences(of: "_", with: "")
            return Double(number).map { $0 * scale }
        }
        return nil
    }

    /// Services only some routes use, on an API without them, would be silently ignored.
    private static func diagnoseUnusedServices(_ arguments: [String: String], of functions: [FunctionInfo], attribute: AttributeSyntax, in context: some MacroExpansionContext) {
        let kinds = Set(functions.map(\.route.taskKind))
        if arguments["socket"] != nil, !kinds.contains("stream") {
            context.diagnose(Diagnostic(node: attribute, message: MacroDiagnostic.unusedSocketConfig))
        }
        if arguments["background"] != nil, kinds.isDisjoint(with: ["upload", "download"]) {
            context.diagnose(Diagnostic(node: attribute, message: MacroDiagnostic.unusedBackground))
        }
    }

    // MARK: - Route Templates

    private static func parseRoutePath(
        _ expression: ExprSyntax?,
        in context: some MacroExpansionContext
    ) -> (literal: String, content: String) {
        guard let expression else { return ("\"\"", "") }
        guard let literal = expression.as(StringLiteralExprSyntax.self) else {
            context.diagnose(Diagnostic(node: expression, message: MacroDiagnostic.pathNotLiteral))
            return (expression.trimmedDescription, "")
        }
        if let interpolation = literal.segments.first(where: { $0.is(ExpressionSegmentSyntax.self) }) {
            context.diagnose(Diagnostic(node: interpolation, message: MacroDiagnostic.pathInterpolation))
        }
        return (literal.trimmedDescription, literal.textContent)
    }

    private static let invalidPathCharacters: Set<Character> = [" ", "<", ">", "|", "\\", "^", "`"]

    private static func placeholders(
        in content: String,
        of pathExpr: ExprSyntax?,
        attribute: AttributeSyntax,
        context: some MacroExpansionContext
    ) -> [String] {
        let node = pathExpr.map(Syntax.init) ?? Syntax(attribute)
        var names: [String] = []
        var literal = ""
        var rest = content[...]
        while let open = rest.firstIndex(of: "{"),
              let close = rest[open...].firstIndex(of: "}") {
            literal += rest[..<open]
            let name = String(rest[rest.index(after: open)..<close])
            if name.isIdentifier {
                if !names.contains(name) { names.append(name) }
            } else {
                context.diagnose(Diagnostic(node: node, message: MacroDiagnostic.invalidPlaceholder(name)))
            }
            rest = rest[rest.index(after: close)...]
        }
        literal += rest

        if let pathExpr {
            if literal.contains(where: invalidPathCharacters.contains) {
                context.diagnose(Diagnostic(node: pathExpr, message: MacroDiagnostic.invalidPathCharacters(path: content)))
            } else if !content.isEmpty, !content.hasPrefix("/") {
                context.diagnose(Diagnostic(node: pathExpr, message: MacroDiagnostic.pathMustStartWithSlash(path: content)))
            }
        }
        return names
    }

    private static func parseRouteQuery(
        _ expression: ExprSyntax,
        in context: some MacroExpansionContext
    ) -> [RouteQueryItem] {
        guard let dictionary = expression.as(DictionaryExprSyntax.self) else {
            context.diagnose(Diagnostic(node: expression, message: MacroDiagnostic.queryNotLiteral))
            return []
        }
        guard case .elements(let elements) = dictionary.content else { return [] } // `[:]`

        return elements.compactMap { element in
            guard let key = element.key.as(StringLiteralExprSyntax.self), key.isPlain,
                  let value = element.value.as(StringLiteralExprSyntax.self), value.isPlain else {
                context.diagnose(Diagnostic(node: element, message: MacroDiagnostic.queryNotLiteral))
                return nil
            }
            let text = value.textContent
            let name = text.hasPrefix("{") && text.hasSuffix("}") ? String(text.dropFirst().dropLast()) : ""
            return RouteQueryItem(
                key: key.trimmedDescription,
                literal: value.trimmedDescription,
                placeholder: name.isIdentifier ? name : nil
            )
        }
    }

    // MARK: - Code Generation

    private static func generateFunction(_ fn: FunctionInfo, in protocolName: String, background: Bool) -> String {
        let signature = "func \(fn.name)(\(parameterList(fn.params))) async throws(\(fn.errorType))"
        switch fn.route.taskKind {
        case "stream", "bytes":
            // `_` lets the compiler infer the wrapper's generics from the declared return type.
            let endpoint = endpointExpression(fn, in: protocolName, success: "_")
            let mock = fn.mockName.map { "if let mock = \($0) { return try await mock(\(fn.params.map(\.internalName).joined(separator: ", "))) }\n        " } ?? ""
            return """
                \(signature) -> \(fn.returnType ?? "Void") {
                    \(mock)return try await \(endpoint).\(fn.route.taskKind == "stream" ? "connect(\(socketExpression(fn.route.options).map { "socket: \($0)" } ?? ""))" : "stream()")
                }
            """
        case "upload", "download":
            return transferFunction(fn, in: protocolName, background: background)
        default:
            let endpoint = endpointExpression(fn, in: protocolName, success: fn.returnType ?? "Void")
            return """
                \(signature)\(fn.returnType.map { " -> \($0)" } ?? "") {
                    let endpoint = \(endpoint)\(mockingExpression(fn))
                    return try await endpoint.data()
                }
            """
        }
    }

    private static func transferFunction(_ fn: FunctionInfo, in protocolName: String, background: Bool) -> String {
        let upload = fn.route.taskKind == "upload"
        let kind = upload ? "Upload" : "Download"
        let success = upload ? (fn.returnType ?? "Void") : "URL"
        let handleGenerics = upload ? "\(success), \(fn.failureType)" : fn.failureType
        let throwing = "async throws(\(fn.errorType)) -> \(success)"
        let params = parameterList(fn.params)
        let arguments = argumentList(fn.params)

        // Handles take the resume data in `start(resumeFrom:)`.
        let handleParams = fn.params.filter { $0.role != .resumeData }
        let endpointParams = upload ? handleParams.filter { ![.body, .uploadFile].contains($0.role) } : handleParams
        let helper = "_\(fn.name)Endpoint"
        let endpoint = "let endpoint = \(helper)(\(argumentList(endpointParams)))\(mockingExpression(fn))"
        // On its own, so an optional body picks the overload that doesn't compile (see `_Route.uploadBody`).
        let content = upload ? "\n        let _uploadContent = \(uploadContent(fn))" : ""
        let resume = fn.params.first { $0.role == .resumeData }.map { "resumeFrom: Beam::_Route.resumeData(\($0.internalName)), " } ?? ""

        let code = """
                private func \(helper)(\(parameterList(endpointParams))) -> Beam::Endpoint<\(success), \(fn.failureType)> {
                    return \(endpointExpression(fn, in: protocolName, success: success))
                }

                func \(fn.name)(\(params)) \(throwing) {
                    try await \(fn.name)(\(arguments.isEmpty ? "" : "\(arguments), ")onProgress: nil)
                }

                func \(fn.name)(\(params.isEmpty ? "" : "\(params), ")onProgress: Beam::ProgressHandler? = nil) \(throwing) {
                    \(endpoint)\(content)
                    return try await endpoint.\(kind.lowercased())(\(upload ? "_uploadContent, " : "")\(resume)onProgress: onProgress)
                }

                func \(fn.name)Task(\(parameterList(handleParams))) -> Beam::\(kind)Task<\(handleGenerics)> {
                    \(endpoint)\(content)
                    return endpoint.\(kind.lowercased())Task(\(upload ? "_uploadContent" : ""))
                }
            """
        guard background else { return code }
        return code + """


                func \(fn.name)BackgroundTask(\(parameterList(handleParams))) -> Beam::Background\(kind)Task<\(handleGenerics)> {
                    \(endpoint)\(content)
                    return endpoint.background\(kind)Task(on: Beam::_Route.background(_config)\(upload ? ", _uploadContent" : ""))
                }
            """
    }

    /// The last case only keeps the expansion well-formed; `uploadWithoutContent` is diagnosed.
    private static func uploadContent(_ fn: FunctionInfo) -> String {
        if let file = fn.params.first(where: { $0.role == .uploadFile }) {
            "Beam::UploadContent.file(Beam::_Route.uploadFile(\(file.internalName)))"
        } else if let body = fn.params.first(where: { $0.role == .body }) {
            "Beam::_Route.uploadBody(\(body.internalName))"
        } else {
            "Beam::UploadContent.body(.data(Foundation::Data()))"
        }
    }

    private static func mockingExpression(_ fn: FunctionInfo) -> String {
        guard let mockName = fn.mockName else { return "" }
        let resume = fn.params.first { $0.role == .resumeData }
        let input = resume == nil ? "_" : "_resume"
        let binding = resume.map { "let \($0.internalName) = _resume ?? Foundation::Data(); " } ?? ""
        let arguments = fn.params.map(\.internalName).joined(separator: ", ")
        return ".mocking(\(mockName).map { mock in .init(_unchecked: { (\(input)) async throws(\(fn.errorType)) in \(binding)return try await mock(\(arguments)) }) })"
    }

    // MARK: - Endpoint

    private static func endpointExpression(_ fn: FunctionInfo, in protocolName: String, success: String) -> String {
        var arguments = ["_config"]
        if let config = configExpression(fn.route.options) { arguments.append("config: \(config)") }
        arguments.append("request: \(requestExpression(fn, in: protocolName))")

        // Interpolated text keeps its indentation as is: align it with the surrounding template.
        return "Beam::Endpoint<\(success), \(fn.failureType)>(\n" + arguments.map { "                \($0)" }.joined(separator: ",\n") + "\n            )"
    }

    /// (route label, `replacing(…)` label, type of an implicit member).
    private static let configOverrides = [
        ("retry", "retry", "Beam::RetryPolicy"),
        ("timeout", "timeout", "Swift::Duration"),
        ("auth", "authPolicy", "Beam::AuthPolicy"),
        ("json", "json", "Beam::JSONCoding"),
    ]

    /// `@Socket` options: (route label, type of an implicit member).
    private static let socketOverrides = [
        ("ping", "Swift::Duration"),
        ("pongTimeout", "Swift::Duration"),
        ("maxMessageSize", "Swift::Int"),
        ("reconnect", "Beam::RetryPolicy"),
        ("protocols", "Swift::Array<Swift::String>"),
        ("jsonFrames", "Beam::SocketConfig.JSONFrames"),
        ("reconnectsOn", "Swift::Set<Swift::Int>"),
    ]

    /// Implicit members get their type: `replacing` takes optionals, so `.none` would be `Optional.none`.
    private static func configExpression(_ options: [String: String]) -> String? {
        overridesExpression(of: "config", configOverrides.map { ($0.0, $0.1, $0.2) }, options)
    }

    private static func socketExpression(_ options: [String: String]) -> String? {
        overridesExpression(of: "socket", socketOverrides.map { ($0.0, $0.0, $0.1) }, options)
    }

    private static func overridesExpression(of config: String, _ table: [(String, String, String)], _ options: [String: String]) -> String? {
        let overrides = table.compactMap { option, label, type in
            options[option].map { "\(label): \($0.hasPrefix(".") ? type + $0 : $0)" }
        }
        return overrides.isEmpty ? nil : "_config.\(config).replacing(\(overrides.joined(separator: ", ")))"
    }

    private static func requestExpression(_ fn: FunctionInfo, in protocolName: String) -> String {
        let kind = fn.route.taskKind
        var arguments = [".\(fn.route.method)"]
        let function: String
        if kind != "stream", let url = fn.params.first(where: { $0.role == .absoluteURL }) {
            function = "request"
            arguments += ["url: Beam::_Route.absoluteURL(\(url.internalName))", "route: \"\(protocolName).\(fn.name)\""]
        } else {
            function = "_request"
            arguments.append(fn.route.path)
            if let values = pathValuesExpression(fn) { arguments.append("values: \(values)") }
            if let routeQuery = routeQueryExpression(fn) { arguments.append("routeQuery: \(routeQuery)") }
            if let query = queryItemsExpression(fn.params) { arguments.append("query: \(query)") }
        }
        if let headers = headersExpression(fn) { arguments.append("headers: \(headers)") }
        if !["upload", "stream"].contains(kind), let body = fn.params.first(where: { $0.role == .body }) {
            arguments.append("body: Beam::_Route.body(\(body.internalName))")
        }
        return "_config.\(function)(\(arguments.joined(separator: ", ")))"
    }

    private static func pathValuesExpression(_ fn: FunctionInfo) -> String? {
        guard !fn.route.pathPlaceholders.isEmpty else { return nil }
        let entries = fn.route.pathPlaceholders.map { "\"\($0)\": \(placeholderValue($0, "path", in: fn))" }
        return "[\(entries.joined(separator: ", "))]"
    }

    private static func routeQueryExpression(_ fn: FunctionInfo) -> String? {
        guard !fn.route.routeQuery.isEmpty else { return nil }
        let entries = fn.route.routeQuery.map { item in
            "\(item.key): \(item.placeholder.map { placeholderValue($0, "queryValue", in: fn) } ?? ".value(\(item.literal))")"
        }
        return "[\(entries.joined(separator: ", "))]"
    }

    /// Falls back to `APIValues.<name>`, so the compiler checks it exists and can be sent.
    private static func placeholderValue(_ name: String, _ helper: String, in fn: FunctionInfo) -> String {
        if let param = fn.params.first(where: { $0.role == .placeholder && ($0.externalName == name || $0.internalName == name) }) {
            return "Beam::_Route.\(helper)(\(param.internalName))"
        }
        return "Beam::_Route.shared(\"\(name)\", Beam::APIValues.\(name))"
    }

    private static func headersExpression(_ fn: FunctionInfo) -> String? {
        var layers = ["_config.headers"]
        if let staticHeaders = fn.route.options["headers"] { layers.append(staticHeaders) }
        for param in fn.params {
            guard case .header(let key) = param.role else { continue }
            layers.append("Beam::_Route.header(\"\(key)\", \(param.internalName))")
        }
        return layers.count == 1 ? nil : "Beam::_Route.headers(\(layers.joined(separator: ", ")))"
    }

    private static func queryItemsExpression(_ params: [ParamInfo]) -> String? {
        let parts = params.compactMap { param -> String? in
            switch param.role {
            case .queryNamed(let key): "Beam::_Route.query(\"\(key)\", \(param.internalName))"
            case .unlabeled: "Beam::_Route.queryItems(\(param.internalName))"
            default: nil
            }
        }
        switch parts.count {
        case 0: return nil
        case 1: return parts[0]
        default: return "[\(parts.joined(separator: ", "))].flatMap { $0 }"
        }
    }

    private static func parameterList(_ params: [ParamInfo]) -> String {
        params.map { param in
            switch param.externalName {
            case param.internalName: "\(param.internalName): \(param.type)"
            case let label?: "\(label) \(param.internalName): \(param.type)"
            case nil: "_ \(param.internalName): \(param.type)"
            }
        }.joined(separator: ", ")
    }

    private static func argumentList(_ params: [ParamInfo]) -> String {
        params.map { param in
            param.externalName.map { "\($0): \(param.internalName)" } ?? param.internalName
        }.joined(separator: ", ")
    }

    // MARK: - Mock Properties

    /// Byte streams aren't mockable: a test can't build a `ByteStream`. Sockets return `WebSocketConnection.mock`.
    private static func assignMockNames(_ functions: inout [FunctionInfo]) {
        let mockable = functions.indices.filter { functions[$0].route.taskKind != "bytes" }
        var nameCounts: [String: Int] = [:]
        for index in mockable { nameCounts[functions[index].name, default: 0] += 1 }

        var used: Set<String> = []
        for index in mockable {
            let fn = functions[index]
            var candidate = "on\(fn.name.capitalizingFirst)"
            if nameCounts[fn.name, default: 0] > 1, let first = fn.params.first {
                candidate += (first.externalName ?? first.internalName).capitalizingFirst
            }
            var name = candidate
            var suffix = 1
            while used.contains(name) {
                suffix += 1
                name = "\(candidate)\(suffix)"
            }
            used.insert(name)
            functions[index].mockName = name
        }
    }

    private static func generateMockProperties(functions: [FunctionInfo]) -> String {
        functions.compactMap { fn -> String? in
            guard let mockName = fn.mockName else { return nil }
            let closureParamTypes = fn.params.map(\.closureParameterType).joined(separator: ", ")
            let successType = fn.route.taskKind == "download" ? "URL" : (fn.returnType ?? "Void")
            return "    var \(mockName): ((\(closureParamTypes)) async throws(\(fn.errorType)) -> \(successType))?\n"
        }.joined()
    }
}

// MARK: - Data Types

/// Decided from the label alone.
enum ParamRole: Equatable {
    case body
    case queryNamed(key: String)
    case header(key: String)
    case placeholder
    case absoluteURL
    case uploadFile
    case resumeData
    case unlabeled
}

struct RouteInfo {
    let method: String
    /// Literal source, quotes included, e.g. `"/users/{id}"`.
    let path: String
    let pathPlaceholders: [String]
    var routeQuery: [RouteQueryItem] = []
    var taskKind: String
    /// Other route arguments as written, by label; those written `nil` are skipped.
    var options: [String: String] = [:]
}

struct RouteQueryItem {
    /// Literal source, e.g. `"lang"`.
    let key: String
    /// Literal source, e.g. `"es"` or `"{locale}"`.
    let literal: String
    let placeholder: String?
}

struct ParamInfo {
    let externalName: String?
    let internalName: String
    let syntax: FunctionParameterSyntax
    let role: ParamRole

    var type: String { syntax.type.trimmedDescription }

    /// `T!` is only valid in declarations, so closure types use `T?`.
    var closureParameterType: String {
        if let unwrapped = syntax.type.withoutAttributes.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return "\(unwrapped.wrappedType.trimmedDescription)?"
        }
        return type
    }
}

struct FunctionInfo {
    let name: String
    let params: [ParamInfo]
    let returnType: String?
    let errorType: String
    let route: RouteInfo
    var mockName: String? = nil

    var failureType: String { "\(errorType)._Failure" }
}

// MARK: - Helpers

extension String {
    var capitalizingFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    var isIdentifier: Bool {
        guard let first, first.isLetter || first == "_" else { return false }
        return allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

extension StringLiteralExprSyntax {
    var isPlain: Bool {
        segments.allSatisfy { $0.is(StringSegmentSyntax.self) }
    }

    var textContent: String {
        segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
    }
}

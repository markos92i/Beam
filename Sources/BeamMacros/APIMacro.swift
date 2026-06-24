//
//  APIMacro.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

/// `@API` generates a concrete struct (`{ProtocolName}Client`) conforming to the protocol.
///
/// Parameter roles are detected by naming convention:
/// - `body` (internal name) → request body encoded as JSON
/// - `query` (external name) → named query parameter (key = internal name)
/// - Type `[URLQueryItem]` → passed directly as query items
/// - `header` (external name) → dynamic HTTP header (key = internal name in PascalCase)
/// - Matches `{name}` in path → path parameter (interpolated)
/// - Everything else → unused by networking (for call-site convenience)
public struct APIMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            throw MacroError.message("@API can only be applied to protocols")
        }

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            throw MacroError.message("@API requires arguments")
        }

        // Parse @API arguments
        var host: String?
        var base: String?
        var headers: String?
        var apiSession: String?
        var auth: String?
        var crash: String?
        var defaultError: String?
        var apiMapper: String?
        var generateMock = false

        for arg in arguments {
            let label = arg.label?.text
            let value = arg.expression.description.trimmingCharacters(in: .whitespaces)
            switch label {
            case "host": host = value
            case "base": base = value
            case "headers": headers = value
            case "session": apiSession = value
            case "auth": auth = value
            case "crash": crash = value
            case "mapper": apiMapper = value
            case "mock": generateMock = value == "true"
            case "error":
                defaultError = value.hasSuffix(".self") ? String(value.dropLast(5)) : value
            default: break
            }
        }

        guard let host else {
            throw MacroError.message("@API requires 'host' parameter")
        }

        let baseStr = base ?? "\"\""
        let protocolName = protocolDecl.name.text
        let clientName = "\(protocolName)Client"
        let failureDefault = defaultError ?? "Void"

        // Collect functions
        var functions: [FunctionInfo] = []

        for member in protocolDecl.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }

            var routeInfo: RouteInfo?
            for attr in funcDecl.attributes {
                guard let attribute = attr.as(AttributeSyntax.self),
                      let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { continue }

                let method = httpMethod(from: name)
                guard let method else { continue }

                guard let args = attribute.arguments?.as(LabeledExprListSyntax.self) else {
                    // No arguments at all: @Get, @Post, etc. — path defaults to ""
                    routeInfo = RouteInfo(method: method, path: "\"\"", taskKind: name == "Socket" ? "stream" : "data", staticHeaders: nil, authPolicy: nil, errorOverride: nil, configOverride: nil, mapperOverride: nil)
                    break
                }
                let argList = Array(args)

                // Determine if first argument is the path (unlabeled) or a named param
                let path: String
                let namedArgs: ArraySlice<LabeledExprSyntax>
                if argList.isEmpty {
                    path = "\"\""
                    namedArgs = argList[...]
                } else if argList[0].label == nil {
                    path = argList[0].expression.description.trimmingCharacters(in: .whitespaces)
                    namedArgs = argList.dropFirst()
                } else {
                    // First arg has a label (e.g. task:, headers:) — no path provided
                    path = "\"\""
                    namedArgs = argList[...]
                }

                // Validate path literal at compile time if it's a pure string
                if let diagnostic = validatePathLiteral(path, in: context, node: attribute) {
                    context.diagnose(diagnostic)
                }

                var taskKind = name == "Socket" ? "stream" : "data"
                var staticHeaders: String? = nil
                var authPolicy: String? = nil
                var routeError: String? = nil
                var routeConfig: String? = nil
                var routeMapper: String? = nil

                for arg in namedArgs {
                    let label = arg.label?.text
                    let value = arg.expression.description.trimmingCharacters(in: .whitespaces)
                    switch label {
                    case "task":
                        taskKind = value.hasPrefix(".") ? String(value.dropFirst()) : value
                    case "headers":
                        staticHeaders = value
                    case "auth":
                        if value == ".optional" { authPolicy = ".optional" }
                    case "error":
                        routeError = value.hasSuffix(".self") ? String(value.dropLast(5)) : value
                    case "config":
                        routeConfig = value
                    case "mapper":
                        routeMapper = value
                    default: break
                    }
                }

                routeInfo = RouteInfo(method: method, path: path, taskKind: taskKind, staticHeaders: staticHeaders, authPolicy: authPolicy, errorOverride: routeError, configOverride: routeConfig, mapperOverride: routeMapper)
                break
            }

            guard let route = routeInfo else { continue }
            let funcInfo = parseFunctionSignature(funcDecl, route: route, defaultFailure: failureDefault)
            functions.append(funcInfo)
        }

        // Generate client struct
        var output = """
        struct \(clientName): \(protocolName), Sendable {
            static let _apiConfiguration = _APIConfiguration(
                host: \(host),
                base: \(baseStr),
                headers: \(headers ?? "[:]")
        """

        if let apiSession { output += ",\n            session: \(apiSession)" }
        if let auth { output += ",\n            auth: \(auth)" }
        if let crash { output += ",\n            crash: \(crash)" }
        if let apiMapper { output += ",\n            mapper: \(apiMapper)" }

        output += """

            )

            private let _config: _APIConfiguration

            init(session: (any SessionProtocol)? = nil) {
                if let session {
                    _config = _APIConfiguration(
                        host: Self._apiConfiguration.host,
                        base: Self._apiConfiguration.base,
                        headers: Self._apiConfiguration.headers,
                        session: session,
                        auth: Self._apiConfiguration.auth,
                        crash: Self._apiConfiguration.crash,
                        mapper: Self._apiConfiguration.mapper,
                        interceptors: Self._apiConfiguration.interceptors
                    )
                } else {
                    _config = Self._apiConfiguration
                }
            }

        """

        for fn in functions {
            output += generateFunction(fn)
            output += "\n"
        }

        output += "}"

        var declarations: [DeclSyntax] = [DeclSyntax(stringLiteral: output)]

        if generateMock {
            declarations.append(DeclSyntax(stringLiteral: generateMockStruct(protocolName: protocolName, functions: functions)))
        }

        return declarations
    }

    // MARK: - Helpers

    private static func httpMethod(from name: String) -> String? {
        switch name {
        case "Get": "get"
        case "Post": "post"
        case "Put": "put"
        case "Delete": "delete"
        case "Patch": "patch"
        case "Head": "head"
        case "Options": "options"
        case "Connect": "connect"
        case "Trace": "trace"
        case "Socket": "get"
        default: nil
        }
    }

    private static func parseFunctionSignature(_ funcDecl: FunctionDeclSyntax, route: RouteInfo, defaultFailure: String) -> FunctionInfo {
        let name = funcDecl.name.text
        var params: [ParamInfo] = []
        var returnType: String? = nil

        // Extract path param names from the route path
        let pathParams = extractPathParams(from: route.path)

        // Parse parameters — detect role by naming convention
        for param in funcDecl.signature.parameterClause.parameters {
            let externalName = param.firstName.text
            let internalName = param.secondName?.text ?? externalName
            let type = param.type.description.trimmingCharacters(in: .whitespaces)

            let role: ParamRole
            if externalName == "body" {
                role = .body
            } else if externalName == "query" {
                role = .queryNamed(key: internalName)
            } else if type == "[URLQueryItem]" {
                role = .queryArray
            } else if externalName == "header" {
                role = .header(key: internalName)
            } else if pathParams.contains(internalName) || pathParams.contains(externalName) {
                role = .path
            } else if externalName == "url" && type == "URL" && route.taskKind != "upload" {
                role = .absoluteURL
            } else {
                role = .ignored
            }

            params.append(ParamInfo(
                externalName: externalName == "_" ? nil : externalName,
                internalName: internalName,
                type: type,
                role: role
            ))
        }

        // Parse return type
        if let returnClause = funcDecl.signature.returnClause {
            returnType = returnClause.type.description.trimmingCharacters(in: .whitespaces)
        }

        // For stream (socket) tasks, unwrap WebSocketConnection<X, Y> → X
        if route.taskKind == "stream", let rt = returnType,
           let extracted = extractFirstGeneric(from: rt, prefix: "WebSocketConnection<") {
            returnType = extracted
        }

        // Parse error type from typed throws: throws(APIError<X>) → extract X
        var failureType = defaultFailure
        if let throwsClause = funcDecl.signature.effectSpecifiers?.throwsClause,
           let thrownType = throwsClause.type {
            let typeStr = thrownType.description.trimmingCharacters(in: .whitespaces)
            // Extract X from APIError<X>
            if typeStr.hasPrefix("APIError<") && typeStr.hasSuffix(">") {
                failureType = String(typeStr.dropFirst("APIError<".count).dropLast())
            } else {
                // If they wrote just the type without APIError wrapper, use it directly
                failureType = typeStr
            }
        } else if route.errorOverride != nil {
            failureType = route.errorOverride!
        }

        return FunctionInfo(
            name: name,
            params: params,
            returnType: returnType,
            failureType: failureType,
            route: route
        )
    }

    /// Extracts the first generic argument from a type string like "UploadTask<ResponseMock, Void>" → "ResponseMock"
    private static func extractFirstGeneric(from type: String, prefix: String) -> String? {
        guard type.hasPrefix(prefix), type.hasSuffix(">") else { return nil }
        let inner = String(type.dropFirst(prefix.count).dropLast())
        // Find the first top-level comma (respecting nested generics)
        var depth = 0
        for (index, char) in inner.enumerated() {
            switch char {
            case "<": depth += 1
            case ">": depth -= 1
            case "," where depth == 0:
                return String(inner.prefix(index)).trimmingCharacters(in: .whitespaces)
            default: break
            }
        }
        // No comma found — single generic argument
        return inner.trimmingCharacters(in: .whitespaces)
    }

    private static func extractPathParams(from path: String) -> Set<String> {
        var params: Set<String> = []
        var cleaned = path
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        var i = cleaned.startIndex
        while i < cleaned.endIndex {
            if cleaned[i] == "{" {
                let start = cleaned.index(after: i)
                if let end = cleaned[start...].firstIndex(of: "}") {
                    params.insert(String(cleaned[start..<end]))
                    i = cleaned.index(after: end)
                    continue
                }
            }
            i = cleaned.index(after: i)
        }
        return params
    }

    // MARK: - Path Validation

    /// Characters that are invalid in a URL path segment.
    private static let invalidPathCharacters: Set<Character> = [" ", "<", ">", "|", "\\", "^", "`"]

    /// Validates a path literal at compile time. Only checks pure string literals
    /// (no interpolation). Emits a warning diagnostic if invalid characters are found.
    private static func validatePathLiteral(
        _ path: String,
        in context: some MacroExpansionContext,
        node: AttributeSyntax
    ) -> Diagnostic? {
        // Only validate pure string literals (starts and ends with quotes, no interpolation markers)
        guard path.hasPrefix("\"") && path.hasSuffix("\"") else { return nil }
        let content = String(path.dropFirst().dropLast())

        // Skip if it contains string interpolation \(...)
        guard !content.contains("\\(") else { return nil }

        // Remove {param} placeholders before checking
        var cleaned = content
        while let open = cleaned.firstIndex(of: "{"),
              let close = cleaned[open...].firstIndex(of: "}") {
            cleaned.removeSubrange(open...close)
        }

        // Check for invalid characters
        if cleaned.contains(where: { invalidPathCharacters.contains($0) }) {
            return Diagnostic(
                node: node,
                message: MacroDiagnostic.invalidPathCharacters(path: content)
            )
        }

        // Check path starts with / (empty path is valid when route is fully defined in base)
        guard content.isEmpty || content.hasPrefix("/") else {
            return Diagnostic(
                node: node,
                message: MacroDiagnostic.pathMustStartWithSlash(path: content)
            )
        }

        return nil
    }

    // MARK: - Code Generation

    private static func generateFunction(_ fn: FunctionInfo) -> String {
        let successType = fn.returnType ?? "Void"
        let failureType = fn.failureType

        // Build parameter list for the generated function
        let paramsStr = fn.params.map { param in
            let ext = param.externalName ?? param.internalName
            if ext == param.internalName {
                return "\(ext): \(param.type)"
            } else {
                return "\(ext) \(param.internalName): \(param.type)"
            }
        }.joined(separator: ", ")

        let throwsStr = "throws(APIError<\(failureType)>)"
        let path = transformPath(fn.route.path, params: fn.params)

        // Body
        let bodyParam = fn.params.first(where: { $0.role == .body })
        let bodyStr: String
        if let bodyParam {
            if bodyParam.type == "HTTPBody" {
                bodyStr = ",\n                body: \(bodyParam.internalName)"
            } else {
                bodyStr = ",\n                body: .json(\(bodyParam.internalName))"
            }
        } else {
            bodyStr = ""
        }

        // Headers
        let headerParams = fn.params.filter { if case .header = $0.role { return true }; return false }
        var extraHeadersStr = ""
        if !headerParams.isEmpty || fn.route.staticHeaders != nil {
            var headerParts: [String] = []
            if let staticHeaders = fn.route.staticHeaders { headerParts.append(staticHeaders) }
            if !headerParams.isEmpty {
                let dynamicPairs = headerParams.map { param -> String in
                    if case .header(let key) = param.role {
                        return "\"\(key)\": \(param.internalName)"
                    }
                    return ""
                }
                let dynamicDict = "[\(dynamicPairs.joined(separator: ", "))]"
                if headerParts.isEmpty {
                    headerParts.append(dynamicDict)
                } else {
                    headerParts = ["\(headerParts[0]).merging(\(dynamicDict)) { _, new in new }"]
                }
            }
            extraHeadersStr = ",\n                extraHeaders: \(headerParts[0])"
        }

        // Query
        let queryArrayParams = fn.params.filter { $0.role == .queryArray }
        let queryNamedParams = fn.params.filter { if case .queryNamed = $0.role { return true }; return false }
        var queryStr = ""
        if !queryArrayParams.isEmpty || !queryNamedParams.isEmpty {
            var parts: [String] = []
            for p in queryArrayParams { parts.append("\(p.internalName)") }
            for p in queryNamedParams {
                if case .queryNamed(let key) = p.role {
                    if p.type.hasSuffix("?") {
                        parts.append("\(p.internalName).map { URLQueryItem(name: \"\(key)\", value: \"\\($0)\") }")
                    } else {
                        parts.append("URLQueryItem(name: \"\(key)\", value: \"\\(\(p.internalName))\")")
                    }
                }
            }

            let hasOptionals = queryNamedParams.contains { $0.type.hasSuffix("?") }

            if queryArrayParams.count == 1 && queryNamedParams.isEmpty {
                queryStr = ",\n                queryItems: \(queryArrayParams[0].internalName)"
            } else if hasOptionals {
                queryStr = ",\n                queryItems: [\(parts.joined(separator: ", "))].compactMap { $0 }"
            } else {
                queryStr = ",\n                queryItems: [\(parts.joined(separator: ", "))]"
            }
        }

        // Auth policy
        var authPolicyStr = ""
        if let policy = fn.route.authPolicy {
            authPolicyStr = ",\n                authPolicy: \(policy)"
        }

        // Config override
        var extraComponentsStr = ""
        if let configOverride = fn.route.configOverride {
            extraComponentsStr = ",\n                extraComponents: [Config(\(configOverride))]"
        }

        // Generate based on task kind
        switch fn.route.taskKind {
        case "stream":
            return generateStreamFunction(fn, successType: successType, failureType: failureType, paramsStr: paramsStr, path: path, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, extraComponentsStr: extraComponentsStr)
        case "upload":
            return generateUploadFunction(fn, successType: successType, failureType: failureType, paramsStr: paramsStr, throwsStr: throwsStr, path: path, bodyStr: bodyStr, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, extraComponentsStr: extraComponentsStr)
        case "download":
            return generateDownloadFunction(fn, failureType: failureType, paramsStr: paramsStr, throwsStr: throwsStr, path: path, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, extraComponentsStr: extraComponentsStr)
        case "bytes":
            return generateBytesFunction(fn, successType: successType, failureType: failureType, paramsStr: paramsStr, throwsStr: throwsStr, path: path, bodyStr: bodyStr, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, extraComponentsStr: extraComponentsStr)
        default:
            return generateDataFunction(fn, successType: successType, failureType: failureType, paramsStr: paramsStr, throwsStr: throwsStr, path: path, bodyStr: bodyStr, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, extraComponentsStr: extraComponentsStr)
        }
    }

    // MARK: - Shared Code-Gen Helpers

    /// Builds the parameter list with an optional progress handler appended.
    private static func progressParams(_ paramsStr: String) -> String {
        paramsStr.isEmpty ? "onProgress: ProgressHandler? = nil" : "\(paramsStr), onProgress: ProgressHandler? = nil"
    }

    /// Generates the function body that wraps an endpoint call with optional progress tracking.
    private static func functionBody(name: String, paramsStr: String, serviceInit: String, callExpr: String, throwsStr: String, returnStr: String) -> String {
        """
            func \(name)(\(paramsStr)) async \(throwsStr)\(returnStr) {
                \(serviceInit)
                \(callExpr)
            }
        """
    }

    // MARK: - Task-Specific Generators

    private static func generateDataFunction(_ fn: FunctionInfo, successType: String, failureType: String, paramsStr: String, throwsStr: String, path: String, bodyStr: String, extraHeadersStr: String, queryStr: String, authPolicyStr: String, extraComponentsStr: String) -> String {
        let hasAbsoluteURL = fn.params.contains { $0.role == .absoluteURL }
        let returnStr = fn.returnType != nil ? " -> \(successType)" : ""
        let serviceInit = buildServiceInit(successType: successType, failureType: failureType, path: path, method: fn.route.method, bodyStr: bodyStr, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, configOverride: fn.route.configOverride, mapperOverride: fn.route.mapperOverride, absoluteURL: hasAbsoluteURL)

        return functionBody(name: fn.name, paramsStr: paramsStr, serviceInit: serviceInit, callExpr: "return try await endpoint.data()", throwsStr: throwsStr, returnStr: returnStr)
    }

    private static func generateUploadFunction(_ fn: FunctionInfo, successType: String, failureType: String, paramsStr: String, throwsStr: String, path: String, bodyStr: String, extraHeadersStr: String, queryStr: String, authPolicyStr: String, extraComponentsStr: String) -> String {
        let returnStr = " -> \(successType)"

        let callExpr: String = if fn.params.contains(where: { $0.internalName == "url" && $0.type == "URL" }) {
            "return try await endpoint.upload(url: url)"
        } else {
            "return try await endpoint.upload()"
        }

        let serviceInit = buildServiceInit(successType: successType, failureType: failureType, path: path, method: fn.route.method, bodyStr: bodyStr, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, configOverride: fn.route.configOverride, mapperOverride: fn.route.mapperOverride)

        // Protocol-conforming overload (no progress)
        let callArgs = fn.params.map { p in
            let ext = p.externalName ?? p.internalName
            return ext == p.internalName ? "\(ext): \(ext)" : "\(ext): \(p.internalName)"
        }.joined(separator: ", ")
        let forwarding = callArgs.isEmpty ? "onProgress: nil" : "\(callArgs), onProgress: nil"

        // Handle factory params: exclude file URL since it's passed to start(url:) at call time
        let handleParams = fn.params.filter { !($0.internalName == "url" && $0.type == "URL") }
        let handleParamsStr = handleParams.map { param in
            let ext = param.externalName ?? param.internalName
            if ext == param.internalName {
                return "\(ext): \(param.type)"
            } else {
                return "\(ext) \(param.internalName): \(param.type)"
            }
        }.joined(separator: ", ")

        return """
            func \(fn.name)(\(paramsStr)) async \(throwsStr)\(returnStr) {
                try await \(fn.name)(\(forwarding))
            }

            func \(fn.name)(\(progressParams(paramsStr))) async \(throwsStr)\(returnStr) {
                \(serviceInit)
                await onProgress?(endpoint.progress)
                \(callExpr)
            }

            func \(fn.name)Task(\(handleParamsStr)) -> UploadTask<\(successType), \(failureType)> {
                \(serviceInit)
                return UploadTask(endpoint: endpoint)
            }
        """
    }

    private static func generateDownloadFunction(_ fn: FunctionInfo, failureType: String, paramsStr: String, throwsStr: String, path: String, extraHeadersStr: String, queryStr: String, authPolicyStr: String, extraComponentsStr: String) -> String {
        let hasAbsoluteURL = fn.params.contains { $0.role == .absoluteURL }
        let callExpr = fn.params.contains(where: { $0.internalName == "data" && $0.externalName == "resumeFrom" })
            ? "return try await endpoint.download(resumeFrom: data)"
            : "return try await endpoint.download()"

        let serviceInit = buildServiceInit(successType: "URL", failureType: failureType, path: path, method: fn.route.method, bodyStr: "", extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, configOverride: fn.route.configOverride, mapperOverride: fn.route.mapperOverride, absoluteURL: hasAbsoluteURL)

        // Protocol-conforming overload (no progress)
        let callArgs = fn.params.map { p in
            let ext = p.externalName ?? p.internalName
            return ext == p.internalName ? "\(ext): \(ext)" : "\(ext): \(p.internalName)"
        }.joined(separator: ", ")
        let forwarding = callArgs.isEmpty ? "onProgress: nil" : "\(callArgs), onProgress: nil"

        return """
            func \(fn.name)(\(paramsStr)) async \(throwsStr) -> URL {
                try await \(fn.name)(\(forwarding))
            }

            func \(fn.name)(\(progressParams(paramsStr))) async \(throwsStr) -> URL {
                \(serviceInit)
                await onProgress?(endpoint.progress)
                \(callExpr)
            }

            func \(fn.name)Task(\(paramsStr)) -> DownloadTask<\(failureType)> {
                \(serviceInit)
                return DownloadTask(endpoint: endpoint)
            }
        """
    }

    private static func generateStreamFunction(_ fn: FunctionInfo, successType: String, failureType: String, paramsStr: String, path: String, extraHeadersStr: String, queryStr: String, authPolicyStr: String, extraComponentsStr: String) -> String {
        let socketInit = buildSocketInit(messageType: successType, failureType: failureType, path: path, method: fn.route.method, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, configOverride: fn.route.configOverride, mapperOverride: fn.route.mapperOverride)
        let throwsStr = "throws(APIError<\(failureType)>)"

        return """
            func \(fn.name)(\(paramsStr)) async \(throwsStr) -> WebSocketConnection<\(successType), \(failureType)> {
                \(socketInit)
                return try await endpoint.connect()
            }
        """
    }

    private static func generateBytesFunction(_ fn: FunctionInfo, successType: String, failureType: String, paramsStr: String, throwsStr: String, path: String, bodyStr: String, extraHeadersStr: String, queryStr: String, authPolicyStr: String, extraComponentsStr: String) -> String {
        let hasAbsoluteURL = fn.params.contains { $0.role == .absoluteURL }

        // Extract element type from ByteStream<T> → T
        let elementType: String
        if let extracted = extractFirstGeneric(from: successType, prefix: "ByteStream<") {
            elementType = extracted
        } else {
            elementType = successType
        }

        let serviceInit = buildServiceInit(successType: elementType, failureType: failureType, path: path, method: fn.route.method, bodyStr: bodyStr, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr, configOverride: fn.route.configOverride, mapperOverride: fn.route.mapperOverride, absoluteURL: hasAbsoluteURL)

        return """
            func \(fn.name)(\(paramsStr)) async \(throwsStr) -> ByteStream<\(elementType)> {
                \(serviceInit)
                return try await endpoint.stream()
            }
        """
    }

    // MARK: - Service Init Builder

    private static func buildServiceInit(
        successType: String,
        failureType: String,
        path: String,
        method: String,
        bodyStr: String,
        extraHeadersStr: String,
        queryStr: String,
        authPolicyStr: String,
        configOverride: String?,
        mapperOverride: String?,
        absoluteURL: Bool = false
    ) -> String {
        // Build headers merging expression
        let headersMerge: String
        if !extraHeadersStr.isEmpty {
            let dictPart = extraHeadersStr
                .replacingOccurrences(of: ",\n                extraHeaders: ", with: "")
            headersMerge = "_config.headers.merging(\(dictPart)) { _, new in new }"
        } else {
            headersMerge = "_config.headers"
        }

        // Auth policy
        let authPolicyExpr: String
        if !authPolicyStr.isEmpty {
            let policyPart = authPolicyStr
                .replacingOccurrences(of: ",\n                authPolicy: ", with: "")
            authPolicyExpr = policyPart
        } else {
            authPolicyExpr = ".required"
        }

        // Config
        let configExpr: String
        if let configOverride {
            configExpr = configOverride
        } else {
            configExpr = ".standard"
        }

        // Serializer: route override > API-level (from _config)
        let mapperExpr: String
        if let mapperOverride {
            mapperExpr = mapperOverride
        } else {
            mapperExpr = "_config.mapper"
        }

        // When absoluteURL is set, the URL param provides the full target — skip host/path/params construction
        if absoluteURL {
            // Body expression (still relevant for POST/PUT with absolute URL)
            let bodyExpr: String
            if !bodyStr.isEmpty {
                let bodyPart = bodyStr
                    .replacingOccurrences(of: ",\n                body: ", with: "")
                bodyExpr = bodyPart
            } else {
                bodyExpr = "nil"
            }

            return """
            let endpoint = Endpoint<\(successType), \(failureType)>(
                        session: _config.session,
                        auth: _config.auth,
                        crash: _config.crash,
                        mapper: \(mapperExpr),
                        config: \(configExpr),
                        authPolicy: \(authPolicyExpr),
                        interceptors: _config.interceptors,
                        logLevel: _config.logLevel,
                        api: APIRequest(
                            method: .\(method),
                            host: url.absoluteString,
                            path: "",
                            query: [],
                            headers: \(headersMerge),
                            body: \(bodyExpr)
                        )
                    )
            """
        }

        // Build query items
        let queryItemsExpr: String
        if !queryStr.isEmpty {
            let itemsPart = queryStr
                .replacingOccurrences(of: ",\n                queryItems: ", with: "")
            queryItemsExpr = itemsPart
        } else {
            queryItemsExpr = "[]"
        }

        // Body expression
        let bodyExpr: String
        if !bodyStr.isEmpty {
            let bodyPart = bodyStr
                .replacingOccurrences(of: ",\n                body: ", with: "")
            bodyExpr = bodyPart
        } else {
            bodyExpr = "nil"
        }

        return """
        let endpoint = Endpoint<\(successType), \(failureType)>(
                    session: _config.session,
                    auth: _config.auth,
                    crash: _config.crash,
                    mapper: \(mapperExpr),
                    config: \(configExpr),
                    authPolicy: \(authPolicyExpr),
                    interceptors: _config.interceptors,
                    logLevel: _config.logLevel,
                    api: APIRequest(
                        method: .\(method),
                        host: _config.host,
                        path: _config.base + \(path),
                        query: \(queryItemsExpr),
                        headers: \(headersMerge),
                        body: \(bodyExpr)
                    )
                )
        """
    }

    // MARK: - Socket Init Builder

    private static func buildSocketInit(
        messageType: String,
        failureType: String,
        path: String,
        method: String,
        extraHeadersStr: String,
        queryStr: String,
        authPolicyStr: String,
        configOverride: String?,
        mapperOverride: String?
    ) -> String {
        // Build headers merging expression
        let headersMerge: String
        if !extraHeadersStr.isEmpty {
            let dictPart = extraHeadersStr
                .replacingOccurrences(of: ",\n                extraHeaders: ", with: "")
            headersMerge = "_config.headers.merging(\(dictPart)) { _, new in new }"
        } else {
            headersMerge = "_config.headers"
        }

        // Build query items
        let queryItemsExpr: String
        if !queryStr.isEmpty {
            let itemsPart = queryStr
                .replacingOccurrences(of: ",\n                queryItems: ", with: "")
            queryItemsExpr = itemsPart
        } else {
            queryItemsExpr = "[]"
        }

        // Auth policy
        let authPolicyExpr: String
        if !authPolicyStr.isEmpty {
            let policyPart = authPolicyStr
                .replacingOccurrences(of: ",\n                authPolicy: ", with: "")
            authPolicyExpr = policyPart
        } else {
            authPolicyExpr = ".required"
        }

        // Config
        let configExpr = configOverride ?? ".standard"

        // Serializer
        let mapperExpr = mapperOverride ?? "_config.mapper"

        return """
        let endpoint = SocketEndpoint<\(messageType), \(failureType)>(
                    session: _config.session,
                    auth: _config.auth,
                    mapper: \(mapperExpr),
                    config: \(configExpr),
                    authPolicy: \(authPolicyExpr),
                    interceptors: _config.interceptors,
                    logLevel: _config.logLevel,
                    api: APIRequest(
                        method: .\(method),
                        host: _config.host,
                        path: _config.base + \(path),
                        query: \(queryItemsExpr),
                        headers: \(headersMerge)
                    )
                )
        """
    }

    private static func transformPath(_ pathLiteral: String, params: [ParamInfo]) -> String {
        var path = pathLiteral
        if path.hasPrefix("\"") && path.hasSuffix("\"") {
            path = String(path.dropFirst().dropLast())
        }
        var result = ""
        var i = path.startIndex
        while i < path.endIndex {
            if path[i] == "{" {
                let start = path.index(after: i)
                guard let end = path[start...].firstIndex(of: "}") else {
                    result.append(path[i])
                    i = path.index(after: i)
                    continue
                }
                let param = String(path[start..<end])
                result += "\\(\(param))"
                i = path.index(after: end)
            } else {
                result.append(path[i])
                i = path.index(after: i)
            }
        }
        return "\"\(result)\""
    }

    // MARK: - Mock Generation

    private static func generateMockStruct(protocolName: String, functions: [FunctionInfo]) -> String {
        let mockName = "\(protocolName)Mock"
        var output = "struct \(mockName): \(protocolName) {\n"

        // Disambiguate overloaded names
        var nameCounts: [String: Int] = [:]
        for fn in functions { nameCounts[fn.name, default: 0] += 1 }

        var nameOccurrences: [String: Int] = [:]

        for fn in functions {
            let baseMockName = "\(fn.name)Mock"
            let mockPropertyName: String

            if nameCounts[fn.name, default: 0] > 1 {
                // Disambiguate by appending first param's external label
                nameOccurrences[fn.name, default: 0] += 1
                if let firstParam = fn.params.first {
                    let label = (firstParam.externalName ?? firstParam.internalName).capitalizingFirst
                    mockPropertyName = "\(fn.name)\(label)Mock"
                } else {
                    mockPropertyName = "\(baseMockName)\(nameOccurrences[fn.name]!)"
                }
            } else {
                mockPropertyName = baseMockName
            }

            let successType = fn.returnType ?? "Void"
            let failureType = fn.failureType
            let throwsClause = "throws(APIError<\(failureType)>)"

            // Closure parameter types
            let closureParamTypes = fn.params.map(\.type).joined(separator: ", ")

            // Closure type: (Params) async throws(APIError<F>) -> Success
            let closureType = "(\(closureParamTypes)) async \(throwsClause) -> \(successType)"

            // fatalError message
            let fatalMessage = "\(mockName).\(fn.name) not stubbed"

            // Default closure that crashes
            let defaultClosure: String
            if fn.params.isEmpty {
                defaultClosure = "{ fatalError(\"\(fatalMessage)\") }"
            } else {
                let wildcards = fn.params.map { _ in "_" }.joined(separator: ", ")
                defaultClosure = "{ \(wildcards) in fatalError(\"\(fatalMessage)\") }"
            }

            // Property declaration
            output += "    var \(mockPropertyName): \(closureType) = \(defaultClosure)\n"

            // Method signature (must match protocol exactly)
            let paramsStr = fn.params.map { param in
                let ext = param.externalName ?? param.internalName
                if ext == param.internalName {
                    return "\(ext): \(param.type)"
                } else {
                    return "\(ext) \(param.internalName): \(param.type)"
                }
            }.joined(separator: ", ")

            let returnStr = fn.returnType != nil ? " -> \(successType)" : ""

            // Call arguments (pass internal names to the closure)
            let callArgs = fn.params.map(\.internalName).joined(separator: ", ")

            // Method body
            output += "\n"
            output += "    func \(fn.name)(\(paramsStr)) async \(throwsClause)\(returnStr) {\n"
            output += "        try await \(mockPropertyName)(\(callArgs))\n"
            output += "    }\n\n"
        }

        output += "}"
        return output
    }
}

// MARK: - Data Types

enum ParamRole: Equatable {
    case body
    case queryNamed(key: String)
    case queryArray
    case header(key: String)
    case path
    case absoluteURL
    case ignored
}

struct RouteInfo {
    let method: String
    let path: String
    let taskKind: String
    let staticHeaders: String?
    let authPolicy: String?
    let errorOverride: String?
    let configOverride: String?
    let mapperOverride: String?
}

struct ParamInfo {
    let externalName: String?
    let internalName: String
    let type: String
    let role: ParamRole
}

struct FunctionInfo {
    let name: String
    let params: [ParamInfo]
    let returnType: String?
    let failureType: String
    let route: RouteInfo
}

// MARK: - Helpers

extension String {
    var capitalizingFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

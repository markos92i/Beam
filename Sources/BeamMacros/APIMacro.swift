//
//  APIMacro.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

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
        var client: String?
        var auth: String?
        var crash: String?
        var defaultError: String?

        for arg in arguments {
            let label = arg.label?.text
            let value = arg.expression.description.trimmingCharacters(in: .whitespaces)
            switch label {
            case "host": host = value
            case "base": base = value
            case "headers": headers = value
            case "client": client = value
            case "auth": auth = value
            case "crash": crash = value
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

                guard let args = attribute.arguments?.as(LabeledExprListSyntax.self) else { continue }
                let argList = Array(args)
                guard !argList.isEmpty else { continue }

                let path = argList[0].expression.description.trimmingCharacters(in: .whitespaces)

                var taskKind = name == "Socket" ? "stream" : "data"
                var staticHeaders: String? = nil
                var authPolicy: String? = nil
                var routeError: String? = nil

                for arg in argList.dropFirst() {
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
                    default: break
                    }
                }

                routeInfo = RouteInfo(method: method, path: path, taskKind: taskKind, staticHeaders: staticHeaders, authPolicy: authPolicy, errorOverride: routeError)
                break
            }

            guard let route = routeInfo else { continue }
            let funcInfo = parseFunctionSignature(funcDecl, route: route, defaultFailure: failureDefault)
            functions.append(funcInfo)
        }

        // Build components array
        var components: [String] = []
        if let headers { components.append("Header(\(headers))") }
        if let client { components.append("Use(\(client))") }
        if let auth { components.append("Auth(\(auth))") }
        if let crash { components.append("Crash(\(crash))") }
        let componentsStr = components.joined(separator: ",\n            ")

        // Generate client struct
        var output = """
        struct \(clientName): \(protocolName), Sendable {
            static let _apiConfiguration = _APIConfiguration(
                host: \(host),
                base: \(baseStr),
                components: [
                    \(componentsStr)
                ]
            )

            private let _config: _APIConfiguration

            init(client: (any ClientProtocol)? = nil) {
                if let client {
                    var components = Self._apiConfiguration.components.filter { !($0 is DSL.Use) }
                    components.insert(Use(client), at: 0)
                    _config = _APIConfiguration(
                        host: Self._apiConfiguration.host,
                        base: Self._apiConfiguration.base,
                        components: components
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

        return [DeclSyntax(stringLiteral: output)]
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
            if internalName == "body" || externalName == "body" {
                role = .body
            } else if externalName == "query" {
                role = .queryNamed(key: internalName)
            } else if type == "[URLQueryItem]" {
                role = .queryArray
            } else if externalName == "header" {
                role = .header(key: internalName)
            } else if pathParams.contains(internalName) || pathParams.contains(externalName) {
                role = .path
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
        let bodyStr = bodyParam != nil ? ",\n                body: .json(\(bodyParam!.internalName))" : ""

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
                    parts.append("URLQueryItem(name: \"\(key)\", value: \"\\(\(p.internalName))\")")
                }
            }
            if queryArrayParams.count == 1 && queryNamedParams.isEmpty {
                queryStr = ",\n                queryItems: \(queryArrayParams[0].internalName)"
            } else {
                queryStr = ",\n                queryItems: [\(parts.joined(separator: ", "))]"
            }
        }

        // Auth policy
        var authPolicyStr = ""
        if let policy = fn.route.authPolicy {
            authPolicyStr = ",\n                authPolicy: \(policy)"
        }

        // Generate based on task kind
        switch fn.route.taskKind {
        case "stream":
            return generateStreamFunction(fn, successType: successType, failureType: failureType, paramsStr: paramsStr, path: path, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr)
        case "upload":
            return generateUploadFunction(fn, successType: successType, failureType: failureType, paramsStr: paramsStr, throwsStr: throwsStr, path: path, bodyStr: bodyStr, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr)
        case "download":
            return generateDownloadFunction(fn, failureType: failureType, paramsStr: paramsStr, throwsStr: throwsStr, path: path, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr)
        default:
            return generateDataFunction(fn, successType: successType, failureType: failureType, paramsStr: paramsStr, throwsStr: throwsStr, path: path, bodyStr: bodyStr, extraHeadersStr: extraHeadersStr, queryStr: queryStr, authPolicyStr: authPolicyStr)
        }
    }

    private static func generateDataFunction(_ fn: FunctionInfo, successType: String, failureType: String, paramsStr: String, throwsStr: String, path: String, bodyStr: String, extraHeadersStr: String, queryStr: String, authPolicyStr: String) -> String {
        let returnStr = fn.returnType != nil ? " -> \(successType)" : ""
        let progressParams = paramsStr.isEmpty ? "onProgress: ProgressHandler?" : "\(paramsStr), onProgress: ProgressHandler?"
        let callArgs = fn.params.map { param in
            let ext = param.externalName ?? param.internalName
            if ext == param.internalName { return "\(ext): \(ext)" }
            return "\(ext): \(param.internalName)"
        }.joined(separator: ", ")
        return """
            func \(fn.name)(\(paramsStr)) async \(throwsStr)\(returnStr) {
                try await \(fn.name)(\(callArgs.isEmpty ? "onProgress: nil" : "\(callArgs), onProgress: nil"))
            }

            func \(fn.name)(\(progressParams)) async \(throwsStr)\(returnStr) {
                let service: Service<\(successType), \(failureType)> = _buildRoute(
                    config: _config,
                    method: .\(fn.route.method),
                    path: \(path)\(bodyStr)\(extraHeadersStr)\(queryStr)\(authPolicyStr)
                )
                let progressTask = onProgress.map { handler in Task { for await p in service.progress { await handler(p) } } }
                defer { progressTask?.cancel() }
                return try await service.data()
            }
        """
    }

    private static func generateUploadFunction(_ fn: FunctionInfo, successType: String, failureType: String, paramsStr: String, throwsStr: String, path: String, bodyStr: String, extraHeadersStr: String, queryStr: String, authPolicyStr: String) -> String {
        let returnStr = " -> \(successType)"
        let callExpr: String
        if fn.params.contains(where: { $0.internalName == "url" && $0.type == "URL" }) {
            callExpr = "return try await service.upload(url: url)"
        } else if fn.params.contains(where: { $0.internalName == "data" && $0.externalName == "resumeFrom" }) {
            callExpr = "return try await service.upload(resumeFrom: data)"
        } else {
            callExpr = "return try await service.upload()"
        }
        let progressParams = paramsStr.isEmpty ? "onProgress: ProgressHandler?" : "\(paramsStr), onProgress: ProgressHandler?"
        let callArgs = fn.params.map { param in
            let ext = param.externalName ?? param.internalName
            if ext == param.internalName { return "\(ext): \(ext)" }
            return "\(ext): \(param.internalName)"
        }.joined(separator: ", ")
        return """
            func \(fn.name)(\(paramsStr)) async \(throwsStr)\(returnStr) {
                try await \(fn.name)(\(callArgs.isEmpty ? "onProgress: nil" : "\(callArgs), onProgress: nil"))
            }

            func \(fn.name)(\(progressParams)) async \(throwsStr)\(returnStr) {
                let service: Service<\(successType), \(failureType)> = _buildRoute(
                    config: _config,
                    method: .\(fn.route.method),
                    path: \(path)\(bodyStr)\(extraHeadersStr)\(queryStr)\(authPolicyStr)
                )
                let progressTask = onProgress.map { handler in Task { for await p in service.progress { await handler(p) } } }
                defer { progressTask?.cancel() }
                \(callExpr)
            }
        """
    }

    private static func generateDownloadFunction(_ fn: FunctionInfo, failureType: String, paramsStr: String, throwsStr: String, path: String, extraHeadersStr: String, queryStr: String, authPolicyStr: String) -> String {
        let callExpr: String
        if fn.params.contains(where: { $0.internalName == "data" && $0.externalName == "resumeFrom" }) {
            callExpr = "return try await service.download(resumeFrom: data)"
        } else {
            callExpr = "return try await service.download()"
        }
        let progressParams = paramsStr.isEmpty ? "onProgress: ProgressHandler?" : "\(paramsStr), onProgress: ProgressHandler?"
        let callArgs = fn.params.map { param in
            let ext = param.externalName ?? param.internalName
            if ext == param.internalName { return "\(ext): \(ext)" }
            return "\(ext): \(param.internalName)"
        }.joined(separator: ", ")
        return """
            func \(fn.name)(\(paramsStr)) async \(throwsStr) -> URL {
                try await \(fn.name)(\(callArgs.isEmpty ? "onProgress: nil" : "\(callArgs), onProgress: nil"))
            }

            func \(fn.name)(\(progressParams)) async \(throwsStr) -> URL {
                let service: Service<URL, \(failureType)> = _buildRoute(
                    config: _config,
                    method: .\(fn.route.method),
                    path: \(path)\(extraHeadersStr)\(queryStr)\(authPolicyStr)
                )
                let progressTask = onProgress.map { handler in Task { for await p in service.progress { await handler(p) } } }
                defer { progressTask?.cancel() }
                \(callExpr)
            }
        """
    }

    private static func generateStreamFunction(_ fn: FunctionInfo, successType: String, failureType: String, paramsStr: String, path: String, extraHeadersStr: String, queryStr: String, authPolicyStr: String) -> String {
        return """
            func \(fn.name)(\(paramsStr)) -> StreamHandle<\(successType), \(failureType)> {
                let service: Service<\(successType), \(failureType)> = _buildRoute(
                    config: _config,
                    method: .\(fn.route.method),
                    path: \(path)\(extraHeadersStr)\(queryStr)\(authPolicyStr)
                )
                return StreamHandle(service: service)
            }
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
}

// MARK: - Data Types

enum ParamRole: Equatable {
    case body
    case queryNamed(key: String)
    case queryArray
    case header(key: String)
    case path
    case ignored
}

struct RouteInfo {
    let method: String
    let path: String
    let taskKind: String
    let staticHeaders: String?
    let authPolicy: String?
    let errorOverride: String?
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

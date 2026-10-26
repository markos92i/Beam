//
//  RouteMacro.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Marker Macro Base

/// Route macros expand to nothing; `@API` reads them.
protocol MarkerMacro: PeerMacro {}

extension MarkerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

// MARK: - HTTP Method Markers

public struct GetMacro: MarkerMacro {}
public struct PostMacro: MarkerMacro {}
public struct PutMacro: MarkerMacro {}
public struct DeleteMacro: MarkerMacro {}
public struct PatchMacro: MarkerMacro {}
public struct HeadMacro: MarkerMacro {}
public struct OptionsMacro: MarkerMacro {}
public struct TraceMacro: MarkerMacro {}
public struct SocketMacro: MarkerMacro {}

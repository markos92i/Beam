//
//  RouteMacro.swift
//  Beam
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Marker Macro Base

/// A no-op peer macro used as a compile-time marker for HTTP route annotations.
/// All route macros (@Get, @Post, etc.) share this identical expansion behavior —
/// they produce no peers; their metadata is consumed by @API at the protocol level.
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
public struct ConnectMacro: MarkerMacro {}
public struct TraceMacro: MarkerMacro {}
public struct SocketMacro: MarkerMacro {}

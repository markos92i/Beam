//
//  Plugin.swift
//  NetworkActor
//
//  Created by Marcos del Castillo Camacho on 15/06/2026.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct NetworkActorMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        APIMacro.self,
        GetMacro.self,
        PostMacro.self,
        PutMacro.self,
        DeleteMacro.self,
        PatchMacro.self,
        HeadMacro.self,
        OptionsMacro.self,
        ConnectMacro.self,
        TraceMacro.self,
        SocketMacro.self,
    ]
}

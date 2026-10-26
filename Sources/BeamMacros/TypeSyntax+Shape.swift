//
//  TypeSyntax+Shape.swift
//  Beam
//
//  The few syntax checks `@API` still makes. Everything that depends on a
//  parameter's *type* is resolved by the compiler through `Beam::_Route`
//  overloads; what remains here is genuinely syntactic: attribute names,
//  `task:` spellings and `T!` (which only exists in source).
//

import SwiftSyntax

extension TypeSyntax {
    var withoutAttributes: TypeSyntax {
        if let attributed = self.as(AttributedTypeSyntax.self) {
            return attributed.baseType.withoutAttributes
        }
        return self
    }

    /// `Get` for `Get`, `Beam.Get` or `Beam::Get`; `nil` for other modules.
    func nominalName(inModule module: String) -> String? {
        let type = withoutAttributes
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            if let selector = identifier.moduleSelector, selector.moduleName.text != module { return nil }
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self),
           let base = member.baseType.as(IdentifierTypeSyntax.self),
           base.genericArgumentClause == nil, base.moduleSelector == nil,
           base.name.text == module {
            return member.name.text
        }
        return nil
    }
}

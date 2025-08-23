import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCBOR
import Foundation

/// Implementation of the `Plain` macro, which provides struct-level serialization functionality.
///
/// This macro supports struct-level usage patterns:
/// 1. Basic: `@Plain` - Generates serialization methods using struct name as wire name
/// 2. Named: `@Plain(name: "...")` - Generates serialization methods with custom wire name
///
/// ## Usage Examples
///
/// ### Struct-level serialization:
/// ```swift
/// @Plain
/// struct User: Codable {
///     let id: Int64
///     let name: String
/// }
///
/// @Plain(name: "custom_user")
/// struct CustomUser: Codable {
///     let id: Int64
///     let email: String
/// }
/// ```
///
/// ### Field-level labels:
/// Field-level encryption labels are handled by the `@Encrypted` macro:
/// ```swift
/// @Encrypted
/// struct Profile: Codable {
///     let id: String
///     @Runar("user") var privateData: String         // This should be handled by @Encrypted
///     @Runar("system") var systemData: String       // This should be handled by @Encrypted
/// }
/// ```
public struct PlainMacro: MemberMacro {
    // MARK: - MemberMacro Implementation (Struct-level)

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Only support structs for member macro
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError("Runar macro can only be applied to structs")
        }

        let structName = structDecl.name.text

        // Check if the struct has Codable conformance
        let hasCodable = structDecl.inheritanceClause?.inheritedTypes.contains { type in
            type.type.as(IdentifierTypeSyntax.self)?.name.text == "Codable"
        } ?? false

        guard hasCodable else {
            throw MacroError("Runar macro requires the struct to explicitly conform to Codable")
        }

        // Extract wire name from macro arguments or use struct name as default
        let wireName = extractWireName(from: node, structName: structName)

        // Handle the case where no name parameter is provided (use struct name)
        let finalWireName = wireName.isEmpty ? structName : wireName

        return [
            """
            /// Bootstrap to register wire name and decoder in TypeNameRegistry
            private static let _runarPlainBootstrap: Void = {
                // Registration will happen at runtime when the struct is used
                // This is a placeholder for macro compilation
            }()

            /// Convert this struct to an AnyValue for serialization
            public func toAnyValue() -> AnyValueType {
                _ = Self._runarPlainBootstrap
                // Placeholder - real implementation will use RunarSerializer.AnyValue
                fatalError("toAnyValue() requires RunarSerializer dependency")
            }

            /// Create this struct from AnyValue
            public static func fromAnyValue(_ anyValue: AnyValueType) async throws -> \(raw: structName) {
                _ = Self._runarPlainBootstrap
                // Placeholder - real implementation will use RunarSerializer.AnyValue
                fatalError("fromAnyValue() requires RunarSerializer dependency")
            }
            """,
        ]
    }

    // MARK: - Helper Functions

    private static func extractWireName(from node: AttributeSyntax, structName: String) -> String {
        // Check if the @Plain macro has a name parameter
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if let label = argument.label?.text,
                   label == "name",
                   let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    return stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text ?? structName
                }
            }
        }

        // If no arguments provided, return empty string to use struct name as default
        if node.arguments == nil {
            return ""
        }

        // Default to struct name if no name parameter provided
        return structName
    }

}

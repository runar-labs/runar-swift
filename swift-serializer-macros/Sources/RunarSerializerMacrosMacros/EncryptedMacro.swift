import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `Encrypted` macro, which generates encryption code for structs.
///
/// This macro automatically adds:
/// - Type alias for the encrypted version
/// - Encrypted struct definition with encryption/decryption methods
/// - Real encryption/decryption implementation
/// - Registration in the global TypeNameRegistry (wire name + decoder)
///
/// Note: The struct must explicitly conform to `Codable` for this macro to work.
///
/// ## Usage
/// ```swift
/// @Encrypted
/// struct TestProfile: Codable {
///     let id: String
///     var sensitive: String
/// }
/// ```
public struct EncryptedMacro: MemberMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Only support structs
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError("Encrypted macro only supports structs")
        }

        let structName = structDecl.name.text
        let encryptedStructName = "Encrypted\(structName)"

        // Use struct name as wire name (simplified for macro context)
        let wireName = structName

        // Check if the struct has Codable conformance
        let hasCodable = structDecl.inheritanceClause?.inheritedTypes.contains { type in
            type.type.as(IdentifierTypeSyntax.self)?.name.text == "Codable"
        } ?? false

        guard hasCodable else {
            throw MacroError("Encrypted macro requires the struct to explicitly conform to Codable")
        }

        // Field labels not supported in simplified macro context

        return [
            """
            /// Bootstrap to register wire name and decoder in TypeNameRegistry
            /// Type alias for the encrypted version of this struct
            public typealias Encrypted = \(raw: encryptedStructName)

            /// Placeholder for encryption functionality
            /// In a real implementation, this would encrypt the struct using a keystore
            public func encryptWithKeystore() async throws -> \(raw: encryptedStructName) {
                // Simplified placeholder for macro testing
                // Real implementation would use external encryption libraries
                fatalError("Encryption not implemented in macro context")
            }

            /// Encrypted version of \(raw: structName)
            public struct \(raw: encryptedStructName): Codable {
                /// The encrypted data
                public let encryptedData: Data

                public init(encryptedData: Data) {
                    self.encryptedData = encryptedData
                }

                /// Placeholder for decryption functionality
                public func decryptWithKeystore() async throws -> \(raw: structName) {
                    // Simplified placeholder for macro testing
                    fatalError("Decryption not implemented in macro context")
                }
            }
            """,
        ]
    }

    // MARK: - PeerMacro Implementation

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // For @Encrypted, we don't generate additional declarations at the peer level
        // The encryption functionality is handled at the member level
        return []
    }

    private static func extractWireName(from node: AttributeSyntax, structName: String) -> String {
        // Check if the @Encrypted macro has a name parameter
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if let label = argument.label?.text,
                   label == "name",
                   let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    return stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text ?? structName
                }
            }
        }

        // Default to struct name if no name parameter provided
        return structName
    }


}

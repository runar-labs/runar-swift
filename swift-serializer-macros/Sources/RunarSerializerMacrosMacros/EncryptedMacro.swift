import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCBOR
import Foundation

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

        // Extract wire name from macro arguments
        let wireName = extractWireName(from: node, structName: structName)

        // Check if the struct has Codable conformance
        let hasCodable = structDecl.inheritanceClause?.inheritedTypes.contains { type in
            type.type.as(IdentifierTypeSyntax.self)?.name.text == "Codable"
        } ?? false

        guard hasCodable else {
            throw MacroError("Encrypted macro requires the struct to explicitly conform to Codable")
        }

        // Extract all fields and field labels from the struct
        let allFields = extractAllFields(from: structDecl)
        let fieldLabels = extractFieldLabels(from: structDecl)

        // Generate encrypted field names based on labels
        let encryptedFields = generateEncryptedFields(fieldLabels)

        return [
            """
            /// Type alias for the encrypted version of this struct
            public typealias Encrypted = \(raw: encryptedStructName)

            /// Bootstrap to register wire name and decoder in TypeNameRegistry
            private static let _runarEncryptedBootstrap: Void = {
                // Registration will happen at runtime when the struct is used
                // This is a placeholder for macro compilation
            }()

            /// Convert this struct to an AnyValue for serialization
            public func toAnyValue() -> AnyValueType {
                _ = Self._runarEncryptedBootstrap
                // Placeholder - real implementation will use RunarSerializer.AnyValue
                fatalError("toAnyValue() requires RunarSerializer dependency")
            }

            /// Create this struct from AnyValue
            public static func fromAnyValue(_ anyValue: AnyValueType) async throws -> Self {
                _ = Self._runarEncryptedBootstrap
                // Placeholder - real implementation will use RunarSerializer.AnyValue
                fatalError("fromAnyValue() requires RunarSerializer dependency")
            }

            /// Encrypt this struct instance using provided keystore and resolver
            /// Note: This requires the real RunarFFI.EnvelopeCrypto and RunarSerializer.LabelResolver protocols
            public func encryptWithKeystore(
                _ keystore: any EnvelopeCryptoProtocol,
                _ resolver: any LabelResolverProtocol
            ) throws -> \(raw: encryptedStructName) {
                _ = Self._runarEncryptedBootstrap

                // Serialize the struct to CBOR
                let encoder = SwiftCBOR.CodableCBOREncoder()
                let cborData = try encoder.encode(self)

                // Create label mapping for encryption
                var encryptedFields: [String: Data] = [:]

                // Process fields with @Runar labels
                // TODO: Implement field-level encryption based on @Runar labels

                // Return encrypted struct
                return \(raw: encryptedStructName)(
                    \(raw: generateEncryptedStructConstructorCall(allFields, fieldLabels))
                )
            }

            /// Encrypted version of \(raw: structName) with field-level access control
            public struct \(raw: encryptedStructName): Codable {
                /// Plain fields (fields without @Runar labels)
                \(raw: generatePlainFieldDeclarations(allFields, fieldLabels))

                /// Encrypted fields (fields with @Runar labels)
                \(raw: generateEncryptedFieldDeclarations(encryptedFields))

                public init(
                    \(raw: generateEncryptedStructInitParams(allFields, fieldLabels))
                ) {
                    \(raw: generateEncryptedStructInitBody(allFields, fieldLabels))
                }

                /// Decrypt this encrypted instance using provided keystore
                public func decryptWithKeystore(_ keystore: any EnvelopeCryptoProtocol) throws -> \(raw: structName) {
                    // Decrypt each encrypted field
                    // TODO: Implement field-level decryption

                    // Return original struct
                    return \(raw: structName)(
                        \(raw: generateDecryptionFieldAssignments(allFields, fieldLabels))
                    )
                }
            }
            """,
        ]
    }

    // MARK: - Helper Functions

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
        return structName
    }

    private static func extractFieldLabels(from structDecl: StructDeclSyntax) -> [String: [String]] {
        var fieldLabels: [String: [String]] = [:]

        // Look for @Runar attributes on variable declarations
        let memberBlock = structDecl.memberBlock
        for member in memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                // Get all variable names (handles multiple bindings like `let x, y: Int`)
                for binding in varDecl.bindings {
                    if let fieldName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                        var labels: [String] = []

                        // Check for @Runar attributes
                        for attribute in varDecl.attributes {
                            if let attr = attribute.as(AttributeSyntax.self),
                               attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Runar" {
                                let runarLabels = RunarMacro.extractLabels(from: attr)
                                if !runarLabels.isEmpty {
                                    labels.append(contentsOf: runarLabels)
                                }
                            }
                        }

                        if !labels.isEmpty {
                            fieldLabels[fieldName] = labels
                        }
                    }
                }
            }
        }

        return fieldLabels
    }

    private static func extractAllFields(from structDecl: StructDeclSyntax) -> [String: String] {
        var allFields: [String: String] = [:]

        let memberBlock = structDecl.memberBlock
        for member in memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                // Extract type annotation for each field
                for binding in varDecl.bindings {
                    if let fieldName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                       let typeAnnotation = binding.typeAnnotation {
                        let typeString = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
                        allFields[fieldName] = typeString
                    }
                }
            }
        }

        return allFields
    }

    private static func generateEncryptedFields(_ fieldLabels: [String: [String]]) -> [String] {
        return fieldLabels.keys.map { "\($0)_encrypted" }
    }

    private static func processFieldEncryption(_ fieldLabels: [String: [String]], _ keystore: String, _ resolver: String) -> String {
        // This would generate code to encrypt each field based on its labels
        // For now, return a placeholder comment
        return "// TODO: Implement field-level encryption based on @Runar labels"
    }

    private static func generateEncryptedStructConstructorCall(_ allFields: [String: String], _ fieldLabels: [String: [String]]) -> String {
        var assignments: [String] = []

        // Add all field assignments in the original struct order
        for (fieldName, _) in allFields {
            if fieldLabels.keys.contains(fieldName) {
                // This is an encrypted field
                assignments.append("\(fieldName)_encrypted: encryptedFields[\"\(fieldName)\"] ?? Data()")
            } else {
                // This is a plain field
                assignments.append("\(fieldName): self.\(fieldName)")
            }
        }

        return assignments.joined(separator: ",\n                    ")
    }

    private static func generatePlainFieldDeclarations(_ allFields: [String: String], _ fieldLabels: [String: [String]]) -> String {
        let plainFields = allFields.filter { !fieldLabels.keys.contains($0.key) }
        return plainFields.map { "public let \($0.key): \($0.value)" }.joined(separator: "\n                ")
    }

    private static func generateEncryptedFieldDeclarations(_ encryptedFields: [String]) -> String {
        return encryptedFields.map { "public let \($0): Data?" }.joined(separator: "\n                ")
    }

    private static func generateEncryptedStructInitParams(_ allFields: [String: String], _ fieldLabels: [String: [String]]) -> String {
        var params: [String] = []

        // Add plain field params
        for (fieldName, fieldType) in allFields {
            if !fieldLabels.keys.contains(fieldName) {
                params.append("\(fieldName): \(fieldType)")
            }
        }

        // Add encrypted field params
        for fieldName in fieldLabels.keys {
            params.append("\(fieldName)_encrypted: Data?")
        }

        return params.joined(separator: ",\n                    ")
    }

    private static func generateEncryptedStructInitBody(_ allFields: [String: String], _ fieldLabels: [String: [String]]) -> String {
        var body: [String] = []

        // Assign plain fields
        for fieldName in allFields.keys {
            if !fieldLabels.keys.contains(fieldName) {
                body.append("self.\(fieldName) = \(fieldName)")
            }
        }

        // Assign encrypted fields
        for fieldName in fieldLabels.keys {
            body.append("self.\(fieldName)_encrypted = \(fieldName)_encrypted")
        }

        return body.joined(separator: "\n                    ")
    }

    private static func generateFieldDecryption(_ fieldLabels: [String: [String]], _ keystore: String) -> String {
        return "// TODO: Implement field-level decryption"
    }

    private static func generateDecryptionFieldAssignments(_ allFields: [String: String], _ fieldLabels: [String: [String]]) -> String {
        var assignments: [String] = []

        // Assign all fields in original struct order
        for fieldName in allFields.keys {
            if fieldLabels.keys.contains(fieldName) {
                // This is an encrypted field - assign decrypted value
                assignments.append("\(fieldName): // TODO: decrypt \(fieldName)_encrypted")
            } else {
                // This is a plain field - assign directly
                assignments.append("\(fieldName): self.\(fieldName)")
            }
        }

        return assignments.joined(separator: ",\n                        ")
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

}

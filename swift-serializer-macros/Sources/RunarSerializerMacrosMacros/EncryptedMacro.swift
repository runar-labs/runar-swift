import SwiftCBOR
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
/// - Registration of element-level encryptor/decryptor for typed containers
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
public struct EncryptedMacro: MemberMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Only support structs
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError("Encrypted macro only supports structs")
        }

        let structName = structDecl.name.text
        let encryptedStructName = "Encrypted\(structName)"

        // Check if the struct has Codable conformance
        let hasCodable = structDecl.inheritanceClause?.inheritedTypes.contains { type in
            type.type.as(SimpleTypeIdentifierSyntax.self)?.name.text == "Codable"
        } ?? false

        guard hasCodable else {
            throw MacroError("Encrypted macro requires the struct to explicitly conform to Codable")
        }

        return [
            """
            /// Bootstrap to register wire name, decoder, and element-level encrypt/decrypt for typed containers
            private static let _runarEncryptedBootstrap: Void = {
                Task {
                    await RunarSerializer.TypeNameRegistry.shared.registerTypeName(\(raw: structName).self, wireName: "\(raw: structName)")
                    await RunarSerializer.TypeNameRegistry.shared.registerDecoder(for: "\(raw: structName)") { data in
                        let decoder = SwiftCBOR.CodableCBORDecoder()
                        return try decoder.decode(\(raw: structName).self, from: data)
                    }
                    await RunarSerializer.ElementCryptoRegistry.shared.register(
                        wireName: "\(raw: structName)",
                        encrypt: { plainCBOR, context in
                            let env = try RunarSerializer.EnvelopeEncryption.encrypt(plainCBOR, context: context)
                            return try RunarSerializer.EnvelopeEncryption.serializeToCBOR(env)
                        },
                        decrypt: { encryptedElementCBOR, keystore in
                            let env = try RunarSerializer.EnvelopeEncryption.deserializeFromCBOR(encryptedElementCBOR)
                            // Prefer network decryption if possible; fallback to first profile key
                            if env.networkId != nil && !env.networkEncryptedKey.isEmpty {
                                return try keystore.decryptWithNetwork(envelopeData: env)
                            }
                            if let firstProfileId = env.profileEncryptedKeys.keys.first {
                                return try keystore.decryptWithProfile(envelopeData: env, profileId: firstProfileId)
                            }
                            throw RunarSerializer.SerializerError.deserializationFailed("No valid decryption method for element")
                        }
                    )
                }
            }()

            /// Type alias for the encrypted version of this struct
            public typealias Encrypted = \(raw: encryptedStructName)

            /// Encrypt this struct using the provided keystore
            public func encryptWithKeystore(_ keystore: RunarKeys.EnvelopeCrypto, resolver: RunarSerializer.LabelResolver) async throws -> \(raw: encryptedStructName) {
                _ = Self._runarEncryptedBootstrap
                // Serialize the struct to CBOR for encrypted types
                let anyValue = RunarSerializer.AnyValue.struct(self)
                let serialized = try anyValue.serialize(context: nil)

                // Use outer envelope encryption with recipients derived from resolver
                let labelInfo = resolver.resolveLabel("\(raw: structName)".lowercased())
                let envelopeData = try keystore.encryptWithEnvelope(data: serialized, networkId: labelInfo?.networkId ?? "test-network", profileIds: labelInfo?.profileIds ?? [])
                return \(raw: encryptedStructName)(encryptedData: envelopeData)
            }

            /// Encrypted version of \(raw: structName)
            public struct \(raw: encryptedStructName): Codable {
                /// The encrypted data
                public let encryptedData: RunarSerializer.EnvelopeEncryptedData

                public init(encryptedData: RunarSerializer.EnvelopeEncryptedData) {
                    self.encryptedData = encryptedData
                }

                /// Decrypt this struct using the provided keystore
                public func decryptWithKeystore(_ keystore: RunarKeys.EnvelopeCrypto) async throws -> \(raw: structName) {
                    _ = \(raw: structName)._runarEncryptedBootstrap

                    // Prefer network decryption if available; otherwise use first profile key
                    let decryptedData: Data
                    if encryptedData.networkId != nil && !encryptedData.networkEncryptedKey.isEmpty {
                        decryptedData = try keystore.decryptWithNetwork(envelopeData: encryptedData)
                    } else if let firstProfileId = encryptedData.profileEncryptedKeys.keys.first {
                        decryptedData = try keystore.decryptWithProfile(envelopeData: encryptedData, profileId: firstProfileId)
                    } else {
                        throw SerializerError.deserializationFailed("No valid decryption method available")
                    }

                    // Deserialize CBOR data back to AnyValue and convert to struct
                    let anyValue = try RunarSerializer.AnyValue.deserialize(decryptedData, keystore: nil)
                    return try await anyValue.asType() as \(raw: structName)
                }
            }
            """,
        ]
    }
}

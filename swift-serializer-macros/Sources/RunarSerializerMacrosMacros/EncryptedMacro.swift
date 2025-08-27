import Foundation
import RunarFFI
import RunarSerializer
import SwiftCBOR
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `Encrypted` macro, aligned with Rust `Encrypt` derive.
/// Generates:
/// - Nested sub-structs per label group (System/User/etc.)
/// - Nested `Encrypted<Struct>` struct containing plain fields + per-label encrypted envelopes
/// - `encryptWithKeystore(_:_: )` on the plain struct
/// - `decryptWithKeystore(_:)` on the encrypted struct
/// - SerializationRegistry registration (wire name + decoder) for the plain struct
public struct EncryptedMacro: MemberMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError("Encrypted macro only supports structs")
        }

        let structName = structDecl.name.text
        let encryptedStructName = "Encrypted\(structName)"
        let wireName = extractWireName(from: node, structName: structName)

        // Require explicit Codable conformance for deterministic encoding
        let hasCodable = structDecl.inheritanceClause?.inheritedTypes.contains { type in
            type.type.as(IdentifierTypeSyntax.self)?.name.text == "Codable"
        } ?? false
        guard hasCodable else { throw MacroError("Encrypted macro requires the struct to explicitly conform to Codable") }

        // Extract ordered fields and labels
        let orderedFields = extractOrderedFields(from: structDecl) // [(name, type)]
        let fieldTypes = Dictionary(uniqueKeysWithValues: orderedFields.map { ($0.name, $0.type) })
        let fieldLabels = extractFieldLabels(from: structDecl) // name -> [labels]
        let labelOrder = makeOrderedLabels(from: fieldLabels) // [label]

        // Build label->fields map preserving declaration order
        let labelToFields: [String: [String]] = {
            var map: [String: [String]] = [:]
            for (name, _) in orderedFields {
                if let labels = fieldLabels[name] {
                    for l in labels {
                        map[l, default: []].append(name)
                    }
                }
            }
            return map
        }()

        // Generate sub-structs per label
        var substructs: [String] = []
        for label in labelOrder {
            guard let fields = labelToFields[label] else { continue }
            let cap = toCamelCase(label)
            let subName = "\(structName)\(cap)Fields"
            let members = fields.compactMap { fname -> String? in
                guard let ty = fieldTypes[fname] else { return nil }
                return "public let \(fname): \(ty)"
            }.joined(separator: "\n                ")
            let sub = """
            struct \(subName): Codable {
            	\(members)
            }
            """
            substructs.append(sub)
        }

        // Plain fields (no labels)
        let plainFields = orderedFields.filter { fieldLabels[$0.name] == nil }
        let plainFieldDecls = plainFields.map { "public let \($0.name): \($0.type)" }.joined(separator: "\n                ")

        // Encrypted fields per label -> EnvelopeEncryptedData?
        let encryptedFieldDecls = labelOrder.map { label in
            "public let \(label)_encrypted: RunarFFI.EnvelopeEncryptedData?"
        }.joined(separator: "\n                ")

        // Encrypted struct init params/body
        let encInitParamsPlain = plainFields.map { "\($0.name): \($0.type)" }
        let encInitParamsEncrypted = labelOrder.map { "\($0)_encrypted: RunarFFI.EnvelopeEncryptedData?" }
        let encInitParams = (encInitParamsPlain + encInitParamsEncrypted).joined(separator: ",\n                    ")
        let encInitBodyPlain = plainFields.map { "self.\($0.name) = \($0.name)" }
        let encInitBodyEncrypted = labelOrder.map { "self.\($0)_encrypted = \($0)_encrypted" }
        let encInitBody = (encInitBodyPlain + encInitBodyEncrypted).joined(separator: "\n                    ")

        // Encrypt: build each sub-struct and envelope if resolver has mapping
        var encryptGroupLines: [String] = []
        for label in labelOrder {
            let cap = toCamelCase(label)
            let subName = "\(structName)\(cap)Fields"
            let fields = labelToFields[label] ?? []
            let subInitArgs = fields.map { "\($0): self.\($0)" }.joined(separator: ", ")
            let line = """
            let \(label)Struct = \(subName)(\(subInitArgs))
            var \(label)Encrypted: RunarFFI.EnvelopeEncryptedData? = nil
            if let info = resolver.resolveLabel("\(label)") {
            	let bytes = try SwiftCBOR.CodableCBOREncoder().encode(\(label)Struct)
            	\(label)Encrypted = try keystore.encryptWithEnvelope(data: bytes, networkId: info.networkId, profileIds: info.profileIds)
            }
            """
            encryptGroupLines.append(line)
        }
        let encReturnArgsPlain = plainFields.map { "\($0.name): self.\($0.name)" }
        let encReturnArgsEncrypted = labelOrder.map { "\($0)_encrypted: \($0)Encrypted" }
        let encReturnArgs = (encReturnArgsPlain + encReturnArgsEncrypted).joined(separator: ",\n                    ")

        // Decrypt: prepare locals with defaults for labeled fields
        let labeledFields = orderedFields.filter { fieldLabels[$0.name] != nil }
        let labeledLocalDefaults = labeledFields.map { f in
            "var \(f.name)_value: \(f.type) = (\(f.type)).runarDefaultValue"
        }.joined(separator: "\n                ")

        // For each label, attempt decrypt and assign into locals
        var decryptBlocks: [String] = []
        for label in labelOrder {
            let fields = labelToFields[label] ?? []
            let cap = toCamelCase(label)
            let subName = "\(structName)\(cap)Fields"
            let assignLines = fields.map { fname in "\(fname)_value = tmp.\(fname)" }.joined(separator: "\n                        ")
            let block = """
            if let group = self.\(label)_encrypted {
                var decrypted: Data? = nil
                if let data = try? keystore.decryptWithNetwork(envelopeData: group) {
                    decrypted = data
                } else if let data = try? keystore.decryptWithProfile(envelopeData: group, profileId: "default") {
                    decrypted = data
                }
                if let data = decrypted {
                    if let tmp = try? SwiftCBOR.CodableCBORDecoder().decode(\(subName).self, from: data) {
                        \(assignLines)
                    }
                }
            }
            """
            decryptBlocks.append(block)
        }

        // Build final initializer call with locals
        let decryptInitArgs = orderedFields.map { f in
            if fieldLabels[f.name] != nil { return "\(f.name): \(f.name)_value" }
            return "\(f.name): self.\(f.name)"
        }.joined(separator: ",\n                        ")

        let members = """
        public typealias Encrypted = \(encryptedStructName)

        private static let _runarEncryptedBootstrap: Void = {
                // Synchronous registrations (non-async)
                RunarSerializer.SerializationRegistry.shared.registerEncryptor(for: Self.self, wireName: "\(wireName)", targetEncryptedWireName: "Encrypted_\(wireName)") { value, keystore, resolver in
                        let enc = try value.encryptWithKeystore(keystore, resolver)
                        let encoder = SwiftCBOR.CodableCBOREncoder()
                        return try encoder.encode(enc)
                }
                // Also register encryptor under Swift type name to avoid races during bootstrap
                RunarSerializer.SerializationRegistry.shared.registerEncryptor(for: Self.self, wireName: "\(structName)", targetEncryptedWireName: "Encrypted_\(wireName)") { value, keystore, resolver in
                        let enc = try value.encryptWithKeystore(keystore, resolver)
                        let encoder = SwiftCBOR.CodableCBOREncoder()
                        return try encoder.encode(enc)
                }
                RunarSerializer.SerializationRegistry.shared.registerDecryptor(for: Encrypted\(structName).self, wireName: "Encrypted_\(wireName)") { data, _ in
                        try SwiftCBOR.CodableCBORDecoder().decode(Encrypted\(structName).self, from: data)
                }
                // Async SerializationRegistry work
                Task {
                        await RunarSerializer.SerializationRegistry.shared.registerWireName(for: Self.self, wireName: "\(wireName)")
                        await RunarSerializer.SerializationRegistry.shared.registerDecoder(for: "\(wireName)") { data in
                                try SwiftCBOR.CodableCBORDecoder().decode(Self.self, from: data)
                        }
                        await RunarSerializer.SerializationRegistry.shared.registerDecoder(for: "\(structName)") { data in
                                try SwiftCBOR.CodableCBORDecoder().decode(Self.self, from: data)
                        }
                        // Also register decoder for encrypted wire name
                        await RunarSerializer.SerializationRegistry.shared.registerDecoder(for: "Encrypted_\(wireName)") { data in
                                try SwiftCBOR.CodableCBORDecoder().decode(Encrypted\(structName).self, from: data)
                        }
                }
        }()

        public func toAnyValue() -> RunarSerializer.AnyValue {
                _ = Self._runarEncryptedBootstrap
                return RunarSerializer.AnyValue.struct(self)
        }

        public static func fromAnyValue(_ anyValue: RunarSerializer.AnyValue) async throws -> Self {
                _ = Self._runarEncryptedBootstrap
                return try await anyValue.asType()
        }

        public func encryptWithKeystore(_ keystore: RunarFFI.EnvelopeCrypto, _ resolver: RunarSerializer.LabelResolver) throws -> \(encryptedStructName) {
                _ = Self._runarEncryptedBootstrap
                \(encryptGroupLines.joined(separator: "\n                "))
                return \(encryptedStructName)(\(encReturnArgs))
        }

        \(substructs.joined(separator: "\n            "))

        public struct \(encryptedStructName): Codable, RunarSerializer.AnyRunarDecryptable {
                \(plainFieldDecls)
                \(encryptedFieldDecls.isEmpty ? "" : "\n                \(encryptedFieldDecls)")

                public init(\(encInitParams)) {
                        \(encInitBody)
                }

                public func decryptWithKeystore(_ keystore: RunarFFI.EnvelopeCrypto) throws -> \(structName) {
                        \(labeledLocalDefaults)
                        \(decryptBlocks.joined(separator: "\n                "))
                        return \(structName)(\(decryptInitArgs))
                }
            // Type-erased hook for AnyValue
            public func _runarDecryptWithKeystore(_ keystore: RunarFFI.EnvelopeCrypto) throws -> Any {
                try decryptWithKeystore(keystore) as \(structName)
            }
        }
        """

        return ["\(raw: members)"]
    }

    // MARK: - Helpers

    private static func extractWireName(from node: AttributeSyntax, structName: String) -> String {
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if let label = argument.label?.text, label == "name",
                   let str = argument.expression.as(StringLiteralExprSyntax.self)?.segments.first?.as(StringSegmentSyntax.self)?.content.text
                {
                    return str
                }
            }
        }
        return structName
    }

    private static func extractOrderedFields(from structDecl: StructDeclSyntax) -> [(name: String, type: String)] {
        var fields: [(String, String)] = []
        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let typeAnnotation = binding.typeAnnotation else { continue }
                let typeString = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
                fields.append((name, typeString))
            }
        }
        return fields
    }

    private static func extractFieldLabels(from structDecl: StructDeclSyntax) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            var labels: [String] = []
            for attribute in varDecl.attributes {
                if let attr = attribute.as(AttributeSyntax.self),
                   attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Runar"
                {
                    labels.append(contentsOf: RunarMacro.extractLabels(from: attr))
                }
            }
            if labels.isEmpty { continue }
            for binding in varDecl.bindings {
                if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                    out[name] = labels
                }
            }
        }
        return out
    }

    private static func toCamelCase(_ s: String) -> String {
        s.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { part in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + String(part.dropFirst())
        }.joined()
    }

    private static func makeOrderedLabels(from fieldLabels: [String: [String]]) -> [String] {
        var set: Set<String> = []
        for labels in fieldLabels.values {
            for l in labels {
                set.insert(l)
            }
        }
        let arr = Array(set)
        return arr.sorted { a, b in
            func rank(_ l: String) -> Int { (l == "system") ? 0 : (l == "user" ? 1 : 2) }
            if rank(a) == rank(b) { return a < b }
            return rank(a) < rank(b)
        }
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else { return [] }
        let structName = structDecl.name.text

        let extEncryptable: DeclSyntax = """
        extension \(raw: structName): RunarSerializer.RunarEncryptable {
        	public typealias Encrypted = \(raw: structName).\(raw: "Encrypted\(structName)")
        }
        """

        let extDecryptable: DeclSyntax = """
        extension \(raw: structName).\(raw: "Encrypted\(structName)"): RunarSerializer.RunarDecryptable {
        	public typealias Decrypted = \(raw: structName)
        }
        """

        return [extEncryptable, extDecryptable]
    }
}

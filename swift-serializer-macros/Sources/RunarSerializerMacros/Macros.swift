import Foundation

/// A simple test macro
@attached(member, names: named(testFunction))
public macro Test() = #externalMacro(module: "RunarSerializerMacrosMacros", type: "TestMacro")

/// Runar macro for unified serialization functionality
/// Usage: @Runar struct MyStruct { ... }
/// Usage: @Runar(name: "custom") struct MyStruct { ... }
@attached(member, names: named(_runarPlainBootstrap), named(toAnyValue), named(fromAnyValue), arbitrary)
public macro Runar() = #externalMacro(module: "RunarSerializerMacrosMacros", type: "RunarMacro")

/// Usage: @Encrypted struct MyStruct { @EncryptedField(label: "user") var sensitive: String }
@attached(member, names: named(Encrypted), named(encryptWithKeystore), arbitrary)
public macro Encrypted() = #externalMacro(module: "RunarSerializerMacrosMacros", type: "EncryptedMacro")

import Foundation

/// A simple test macro
@attached(member, names: named(testFunction))
public macro Test() = #externalMacro(module: "RunarSerializerMacrosMacros", type: "TestMacro")

/// Plain macro for struct-level serialization functionality
/// Usage: @Plain struct MyStruct { ... }
/// Usage: @Plain(name: "custom") struct MyStruct { ... }
@attached(member, names: named(_runarPlainBootstrap), named(toAnyValue), named(fromAnyValue), arbitrary)
public macro Plain(name: String = "") = #externalMacro(module: "RunarSerializerMacrosMacros", type: "PlainMacro")

/// Runar macro for field-level label mapping
/// Usage: @Runar("user") var field: String
/// Usage: @Runar("user, system") var field: String
@attached(peer)
public macro Runar(_ label: String) = #externalMacro(module: "RunarSerializerMacrosMacros", type: "RunarMacro")

/// Usage: @Encrypted(name: "custom") struct MyStruct { ... }
@attached(member, names: named(Encrypted), named(encryptWithKeystore), arbitrary)
public macro Encrypted(name: String) = #externalMacro(module: "RunarSerializerMacrosMacros", type: "EncryptedMacro")

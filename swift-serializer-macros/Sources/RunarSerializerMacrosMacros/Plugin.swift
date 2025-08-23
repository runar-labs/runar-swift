import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct RunarSerializerMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        TestMacro.self,
        RunarMacro.self,
        EncryptedMacro.self,
    ]
}

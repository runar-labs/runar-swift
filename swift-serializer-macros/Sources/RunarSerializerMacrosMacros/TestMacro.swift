import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TestMacro: MemberMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf _: some DeclGroupSyntax,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [
            """
            public func testFunction() {
                print("Hello from macro!")
            }
            """,
        ]
    }
}

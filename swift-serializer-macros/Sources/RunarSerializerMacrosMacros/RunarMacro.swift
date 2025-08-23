import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `Runar` macro for field-level label mapping.
///
/// This macro is used to annotate individual fields with encryption labels.
/// It supports single labels and multiple comma-separated labels.
///
/// ## Usage Examples
///
/// ### Single label:
/// ```swift
/// @Encrypted
/// struct Profile: Codable {
///     let id: String
///     @Runar("user") var privateData: String
///     @Runar("system") var metadata: String
/// }
/// ```
///
/// ### Multiple labels:
/// ```swift
/// @Encrypted
/// struct Document: Codable {
///     let id: String
///     @Runar("user, system") var accessibleByMultiple: String
///     @Runar("admin") var adminOnly: String
/// }
/// ```
public struct RunarMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // For field-level @Runar usage, we don't generate additional declarations
        // The label information is processed by the EncryptedMacro during expansion
        // This macro serves as a marker for field-level encryption labels

        // Validate that the macro is applied to a variable declaration
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            throw MacroError("@Runar can only be applied to variable declarations")
        }

        // Validate that the variable has a name
        guard let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw MacroError("@Runar requires a variable with a valid identifier")
        }

        _ = identifier.identifier.text

        // Extract labels from the macro arguments
        let labels = extractLabels(from: node)

        if labels.isEmpty {
            throw MacroError("@Runar requires at least one label (e.g., @Runar(\"user\"))")
        }

        // For now, return empty declarations - the label information will be
        // processed by the EncryptedMacro when it expands
        return []
    }

    /// Extracts labels from @Runar macro arguments
    public static func extractLabels(from node: AttributeSyntax) -> [String] {
        guard let arguments = node.arguments else {
            return []
        }

        // Handle string literal arguments like @Runar("user") or @Runar("user, system")
        if let stringLiteral = arguments.as(StringLiteralExprSyntax.self) {
            if let content = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text {
                return content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }

        // Handle labeled arguments (if needed for future extensions)
        if let labeledArgs = arguments.as(LabeledExprListSyntax.self) {
            for argument in labeledArgs {
                if let label = argument.label?.text,
                   (label == "label" || label == "labels"),
                   let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    if let content = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text {
                        return content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    }
                }
            }
        }

        return []
    }
}

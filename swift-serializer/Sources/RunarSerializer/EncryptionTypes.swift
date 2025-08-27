import Foundation

// MARK: - Encryption Types

/// Information about a label's key mapping
public struct LabelKeyInfo {
    public let profileIds: [String]
    public let networkId: String?

    public init(profileIds: [String], networkId: String?) {
        self.profileIds = profileIds
        self.networkId = networkId
    }
}

/// Protocol for resolving labels to key information
public protocol LabelResolver {
    /// Resolve a field label to key information
    func resolveLabel(_ label: String) -> LabelKeyInfo?
}

// MARK: - Default Values For Decryption Fallback

/// Types that can provide a sensible default value for access-controlled decryption fallbacks.
/// This mirrors Rust's `Default` derive usage when fields are not accessible.
public protocol RunarDefault {
    static var runarDefaultValue: Self { get }
}

extension Optional: RunarDefault {
    public static var runarDefaultValue: Optional<Wrapped> { nil }
}

extension String: RunarDefault {
    public static var runarDefaultValue: String { "" }
}

extension Bool: RunarDefault {
    public static var runarDefaultValue: Bool { false }
}

extension Data: RunarDefault {
    public static var runarDefaultValue: Data { Data() }
}

extension Int: RunarDefault {
    public static var runarDefaultValue: Int { 0 }
}

extension Int64: RunarDefault {
    public static var runarDefaultValue: Int64 { 0 }
}

extension Int32: RunarDefault {
    public static var runarDefaultValue: Int32 { 0 }
}

extension Int16: RunarDefault {
    public static var runarDefaultValue: Int16 { 0 }
}

extension Int8: RunarDefault {
    public static var runarDefaultValue: Int8 { 0 }
}

extension UInt: RunarDefault {
    public static var runarDefaultValue: UInt { 0 }
}

extension UInt64: RunarDefault {
    public static var runarDefaultValue: UInt64 { 0 }
}

extension UInt32: RunarDefault {
    public static var runarDefaultValue: UInt32 { 0 }
}

extension UInt16: RunarDefault {
    public static var runarDefaultValue: UInt16 { 0 }
}

extension UInt8: RunarDefault {
    public static var runarDefaultValue: UInt8 { 0 }
}

extension Float: RunarDefault {
    public static var runarDefaultValue: Float { 0 }
}

extension Double: RunarDefault {
    public static var runarDefaultValue: Double { 0 }
}

extension Array: RunarDefault {
    public static var runarDefaultValue: [Element] { [] }
}

extension Dictionary: RunarDefault {
    public static var runarDefaultValue: [Key: Value] { [:] }
}

// MARK: - LabelResolver convenience

public extension LabelResolver {
    func canResolve(_ label: String) -> Bool { resolveLabel(label) != nil }
}

// MARK: - Dynamic decrypt/encrypt interoperability for AnyValue

/// Type-erased decryptable interface so decoders can return encrypted structs
/// and callers can request the plain type via AnyValue APIs.
public protocol AnyRunarDecryptable {
    func runarDecryptWithKeystore(_ keystore: EnvelopeCrypto) throws -> Any
}

/// Type-erased encryptable-to-CBOR interface used by AnyValue to produce
/// Encrypted<T> CBOR when a SerializationContext is provided.
public protocol RunarEncryptableCBOR {
    func runarEncryptCBOR(context: SerializationContext) throws -> Data
}

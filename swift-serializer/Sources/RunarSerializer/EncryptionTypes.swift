import Foundation
import RunarFFI

// MARK: - Encryption Types

// Enhanced label resolver protocol for field-level encryption
public struct LabelKeyInfo {
    public let profileIds: [String]
    public let networkId: String?
    
    public init(profileIds: [String], networkId: String?) {
        self.profileIds = profileIds
        self.networkId = networkId
    }
}

// MARK: - Standard Encryption Labels

/// Standard encryption labels for field-level access control
/// These match the Rust implementation exactly
public enum RunarLabel: String, CaseIterable {
    case system = "system"
    case user = "user"
    case search = "search"
    case systemOnly = "system_only"
    
    /// Convert label to CamelCase for sub-struct naming
    public var camelCase: String {
        switch self {
        case .system: return "System"
        case .user: return "User"
        case .search: return "Search"
        case .systemOnly: return "SystemOnly"
        }
    }
    
    /// Priority for deterministic ordering (matches Rust)
    public var priority: Int {
        switch self {
        case .system: return 0
        case .user: return 1
        case .search, .systemOnly: return 2
        }
    }
}

// LabelResolver is now imported from RunarFFI

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

// Note: LabelResolver is now imported from RunarFFI
// The convenience methods are no longer needed as the FFI protocol has a different signature

// MARK: - LabelResolver Adapter for FFI Compatibility

/// Adapter to convert FFI LabelResolver to the format expected by the serializer
public struct LabelResolverAdapter: RunarFFI.LabelResolver {
    private let resolver: RunarFFI.LabelResolver
    
    public init(_ resolver: RunarFFI.LabelResolver) {
        self.resolver = resolver
    }
    
    public func resolveLabel(_ label: String) throws -> String {
        try resolver.resolveLabel(label)
    }
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

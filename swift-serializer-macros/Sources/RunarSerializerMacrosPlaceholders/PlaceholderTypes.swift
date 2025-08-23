import Foundation

// MARK: - Placeholder Types for Macro Compilation

/// Placeholder for RunarSerializer.AnyValue
/// This is used only for macro compilation and will be replaced by the real type at runtime
public enum AnyValue {
    case placeholder

    public static func `struct`(_ value: Any) -> AnyValue {
        return .placeholder
    }

    public func asType<T>() async throws -> T {
        fatalError("AnyValue placeholder - real implementation required at runtime")
    }
}

/// Placeholder for RunarFFI.EnvelopeCrypto
/// This is used only for macro compilation and will be replaced by the real protocol at runtime
public protocol EnvelopeCrypto {
    func encryptWithEnvelope(data: Foundation.Data, networkId: String?, profileIds: [String]) throws -> Any
    func decryptWithProfile(envelopeData: Any, profileId: String) throws -> Foundation.Data
    func decryptWithNetwork(envelopeData: Any) throws -> Foundation.Data
}

/// Placeholder for RunarSerializer.LabelResolver
/// This is used only for macro compilation and will be replaced by the real protocol at runtime
public protocol LabelResolver {
    func resolveLabel(_ label: String) -> Any?
}

/// CBOR Encoder placeholder for macro compilation
/// This provides a basic CBOR encoding interface for macros
public class CodableCBOREncoder {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Foundation.Data {
        // This is a placeholder - the real implementation would use SwiftCBOR
        // For macro compilation, just return empty data
        return Foundation.Data()
    }
}

/// Make placeholder types available at module level
public typealias EnvelopeCryptoProtocol = EnvelopeCrypto
public typealias LabelResolverProtocol = LabelResolver
public typealias AnyValueType = AnyValue

import Foundation
import RunarFFI

// MARK: - Type Registration and Resolution System
// Equivalent to Rust's registry.rs

/// Global type registry for serialization/deserialization
/// Thread-safe registry matching Rust's global registries
public final class SerializerRegistry {
    public static let shared = SerializerRegistry()

    // Thread-safe storage using concurrent maps
    private let decryptRegistry = ConcurrentMap<String, (Data, EnvelopeCrypto) throws -> Any>()
    private let encryptRegistry = ConcurrentMap<String, (Any, EnvelopeCrypto, LabelResolver) throws -> Data>()
    private let jsonRegistry = ConcurrentMap<String, (Data) throws -> Any>()
    private let wireNameRegistry = ConcurrentMap<String, String>() // rust_name -> wire_name

    private init() {}

    // MARK: - Decryptor Registration

    /// Register a decryptor for a type
    public func registerDecryptor<T: Decodable>(
        for type: T.Type,
        wireName: String? = nil,
        decryptor: @escaping (Data, EnvelopeCrypto) throws -> T
    ) {
        let typeName = String(describing: type)
        let registryKey = wireName ?? typeName

        decryptRegistry[registryKey] = { data, crypto in
            try decryptor(data, crypto)
        }
    }

    /// Get decryptor for a wire name
    public func decryptor(for wireName: String) -> ((Data, EnvelopeCrypto) throws -> Any)? {
        decryptRegistry[wireName]
    }

    // MARK: - Encryptor Registration

    /// Register an encryptor for a type
    public func registerEncryptor<T: Encodable>(
        for type: T.Type,
        wireName: String? = nil,
        encryptor: @escaping (T, EnvelopeCrypto, LabelResolver) throws -> Data
    ) {
        let typeName = String(describing: type)
        let registryKey = wireName ?? typeName

        encryptRegistry[registryKey] = { value, crypto, resolver in
            guard let typedValue = value as? T else {
                throw SerializerError.typeMismatch("Expected \(typeName), got \(String(describing: Swift.type(of: value)))")
            }
            return try encryptor(typedValue, crypto, resolver)
        }
    }

    /// Get encryptor for a wire name
    public func encryptor(for wireName: String) -> ((Any, EnvelopeCrypto, LabelResolver) throws -> Data)? {
        encryptRegistry[wireName]
    }

    // MARK: - JSON Conversion Registration

    /// Register JSON converter for a type
    public func registerJSONConverter<T: Decodable>(
        for type: T.Type,
        wireName: String? = nil,
        converter: @escaping (Data) throws -> T
    ) {
        let typeName = String(describing: type)
        let registryKey = wireName ?? typeName

        jsonRegistry[registryKey] = { data in
            try converter(data)
        }
    }

    /// Get JSON converter for a wire name
    public func jsonConverter(for wireName: String) -> ((Data) throws -> Any)? {
        jsonRegistry[wireName]
    }

    // MARK: - Wire Name Registration

    /// Register wire name mapping
    public func registerWireName(rustName: String, wireName: String) {
        wireNameRegistry[rustName] = wireName
    }

    /// Get wire name for rust name
    public func wireName(for rustName: String) -> String {
        wireNameRegistry[rustName] ?? rustName
    }

    /// Get rust name for wire name (reverse lookup)
    public func rustName(for wireName: String) -> String? {
        for (rustName, mappedWireName) in wireNameRegistry {
            if mappedWireName == wireName {
                return rustName
            }
        }
        return nil
    }

    // MARK: - Registry Introspection

    /// Get all registered wire names
    public func allWireNames() -> [String] {
        Array(decryptRegistry.keys)
    }

    /// Check if a wire name is registered
    public func isRegistered(wireName: String) -> Bool {
        decryptRegistry[wireName] != nil
    }

    /// Clear all registrations (mainly for testing)
    public func clearAll() {
        decryptRegistry.clear()
        encryptRegistry.clear()
        jsonRegistry.clear()
        wireNameRegistry.clear()
    }
}

// MARK: - Thread-Safe Concurrent Map

/// Thread-safe dictionary wrapper
private final class ConcurrentMap<Key: Hashable, Value>: Sequence {
    private var storage = [Key: Value]()
    private let lock = NSLock()

    subscript(key: Key) -> Value? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage[key] = newValue
        }
    }

    var keys: Dictionary<Key, Value>.Keys {
        lock.lock()
        defer { lock.unlock() }
        return storage.keys
    }

    func makeIterator() -> Dictionary<Key, Value>.Iterator {
        lock.lock()
        defer { lock.unlock() }
        return storage.makeIterator()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

// MARK: - Helper Functions

/// Convert Any value to AnyValue using appropriate constructor
private func AnyValueFromAny(_ value: Any) throws -> AnyValue {
    if let codableValue = value as? Codable {
        return AnyValue.struct(codableValue)
    } else if let dataValue = value as? Data {
        return AnyValue.bytes(dataValue)
    } else if let stringValue = value as? String {
        return AnyValue.primitive(stringValue)
    } else if let intValue = value as? Int64 {
        return AnyValue.primitive(intValue)
    } else if let boolValue = value as? Bool {
        return AnyValue.primitive(boolValue)
    } else {
        throw SerializerError.typeMismatch("Unsupported type for AnyValue conversion: \(type(of: value))")
    }
}

// MARK: - Enhanced AnyValue with Registry Support

extension AnyValue {
    /// Create AnyValue with registry-based type resolution
    public static func fromRegistry(wireName: String, data: Data, crypto: EnvelopeCrypto? = nil) throws -> AnyValue {
        guard let decryptor = SerializerRegistry.shared.decryptor(for: wireName) else {
            throw SerializerError.deserializationFailed("No decryptor registered for wire name: \(wireName)")
        }

        if let crypto = crypto {
            let decryptedValue = try decryptor(data, crypto)
            return try AnyValueFromAny(decryptedValue)
        } else {
            // For non-encrypted data, try JSON conversion
            if let jsonConverter = SerializerRegistry.shared.jsonConverter(for: wireName) {
                let convertedValue = try jsonConverter(data)
                return try AnyValueFromAny(convertedValue)
            } else {
                throw SerializerError.deserializationFailed("No converter available for wire name: \(wireName)")
            }
        }
    }

    /// Serialize with registry-based type resolution
    public func serializeWithRegistry(wireName: String? = nil, crypto: EnvelopeCrypto? = nil, resolver: LabelResolver? = nil) throws -> Data {
        let registryWireName = wireName ?? typeName

        if crypto != nil && resolver != nil {
            // Check if encryptor is available (for future implementation)
            _ = SerializerRegistry.shared.encryptor(for: registryWireName)

            // This would need access to the underlying value, which requires changes to AnyValue structure
            // For now, fall back to regular serialization
            return try serialize(context: nil)
        } else {
            return try serialize(context: nil)
        }
    }
}

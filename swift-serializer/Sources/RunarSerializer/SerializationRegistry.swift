import Foundation
import SwiftFFI

/// Unified actor-based registry for all serialization functionality
public actor SerializationRegistry {
    // MARK: - Wire Name Management

    private nonisolated(unsafe) var swiftTypeToWireName: [String: String] = [:]
    private nonisolated(unsafe) var wireNameToSwiftType: [String: Any.Type] = [:]
    private nonisolated(unsafe) var encryptedWireByPlainWire: [String: String] = [:]

    // MARK: - Serialization Functions

    private nonisolated(unsafe) var wireNameToDecryptor: [String: @Sendable (Data, CommonKeyManager) async throws -> Any] = [:]
    private nonisolated(unsafe) var wireNameToEncryptor: [String: @Sendable (Any, CommonKeyManager, LabelResolver) async throws -> Data] = [:]

    // MARK: - Deserialization Functions

    private nonisolated(unsafe) var wireNameToDecoder: [String: @Sendable (Data) throws -> Any] = [:]

    // MARK: - JSON Conversion

    private var wireNameToJsonConverter: [String: @Sendable @MainActor (AnyValue) async throws -> Any] = [:]

    // MARK: - Cached Lookups (for synchronous access)

    private nonisolated(unsafe) var wireNameCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 1000 // Reasonable limit
        return cache
    }()

    // MARK: - Initialization

    public static let shared = SerializationRegistry()

    private init() {
        Task {
            await setupPrimitiveMappings()
            await setupContainerMappings()
        }
    }

    // MARK: - Wire Name Management

    public func registerWireName<T>(for _: T.Type, wireName: String) {
        let swiftName = String(describing: T.self)
        swiftTypeToWireName[swiftName] = wireName
        wireNameToSwiftType[wireName] = T.self
        wireNameCache.setObject(NSString(string: wireName), forKey: NSString(string: swiftName))
    }

    public func wireName(for swiftTypeName: String) -> String? {
        // Fast cache lookup first
        if let cached = wireNameCache.object(forKey: NSString(string: swiftTypeName)) {
            return cached as String
        }
        return swiftTypeToWireName[swiftTypeName]
    }

    /// Synchronous wire name lookup for performance-critical code
    public nonisolated func wireNameSync(for swiftTypeName: String) -> String? {
        // Only check cache for synchronous access
        wireNameCache.object(forKey: NSString(string: swiftTypeName)) as String?
    }

    public func swiftType(for wireName: String) -> Any.Type? {
        wireNameToSwiftType[wireName]
    }

    public func encryptedWireName(for plainWireName: String) -> String? {
        encryptedWireByPlainWire[plainWireName]
    }

    // MARK: - Serialization Functions

    @preconcurrency
    public func registerDecryptor<T: Decodable & Sendable>(
        for _: T.Type,
        wireName: String? = nil,
        decryptor: @escaping @Sendable (Data, CommonKeyManager) async throws -> T
    ) {
        let registryKey = wireName ?? String(describing: T.self)
        wireNameToDecryptor[registryKey] = { [decryptor] data, keystore in
            try await decryptor(data, keystore)
        }
    }

    @preconcurrency
    public func registerEncryptor<T: Encodable & Sendable>(
        for _: T.Type,
        wireName: String? = nil,
        targetEncryptedWireName: String? = nil,
        encryptor: @escaping @Sendable (T, CommonKeyManager, LabelResolver) async throws -> Data
    ) {
        let registryKey = wireName ?? String(describing: T.self)
        let expectedTypeName = String(describing: T.self)
        wireNameToEncryptor[registryKey] = { [encryptor, expectedTypeName] value, keystore, resolver in
            guard let typedValue = value as? T else {
                throw SerializerError.typeMismatch("Expected \(expectedTypeName), got \(String(describing: Swift.type(of: value)))")
            }
            return try await encryptor(typedValue, keystore, resolver)
        }

        if let encryptedName = targetEncryptedWireName {
            encryptedWireByPlainWire[registryKey] = encryptedName
        }
    }

    public func decryptor(for wireName: String) -> (@Sendable (Data, CommonKeyManager) async throws -> Any)? {
        wireNameToDecryptor[wireName]
    }

    public func encryptor(for wireName: String) -> (@Sendable (Any, CommonKeyManager, LabelResolver) async throws -> Data)? {
        wireNameToEncryptor[wireName]
    }

    // MARK: - Deserialization Functions

    @preconcurrency
    public func registerDecoder(
        for wireName: String,
        decoder: @escaping @Sendable (Data) throws -> (any Decodable & Sendable)
    ) {
        wireNameToDecoder[wireName] = { [decoder] data in
            try decoder(data)
        }
    }

    public func decoder(for wireName: String) -> (@Sendable (Data) throws -> Any)? {
        wireNameToDecoder[wireName]
    }

    // MARK: - JSON Conversion

    public func registerJsonConverter(
        for wireName: String,
        converter: @escaping @Sendable @MainActor (AnyValue) async throws -> Any
    ) {
        wireNameToJsonConverter[wireName] = converter
    }

    public func jsonConverter(for wireName: String) -> (@Sendable @MainActor (AnyValue) async throws -> Any)? {
        wireNameToJsonConverter[wireName]
    }

    // MARK: - Setup Functions

    private func setupPrimitiveMappings() {
        registerWireName(for: String.self, wireName: "string")
        registerWireName(for: Bool.self, wireName: "bool")
        registerWireName(for: Int8.self, wireName: "i8")
        registerWireName(for: Int16.self, wireName: "i16")
        registerWireName(for: Int32.self, wireName: "i32")
        registerWireName(for: Int64.self, wireName: "i64")
        registerWireName(for: UInt8.self, wireName: "u8")
        registerWireName(for: UInt16.self, wireName: "u16")
        registerWireName(for: UInt32.self, wireName: "u32")
        registerWireName(for: UInt64.self, wireName: "u64")
        registerWireName(for: Float.self, wireName: "f32")
        registerWireName(for: Double.self, wireName: "f64")
        registerWireName(for: Int.self, wireName: "i64") // Apple 64-bit normalization
        registerWireName(for: UInt.self, wireName: "u64") // Apple 64-bit normalization
        registerWireName(for: Date.self, wireName: "date")
        registerWireName(for: Data.self, wireName: "bytes")
    }

    private func setupContainerMappings() {
        wireNameToSwiftType["list<any>"] = [AnyValue].self
        wireNameToSwiftType["map<string,any>"] = [String: AnyValue].self
    }

    // MARK: - Synchronous Registration Methods (for startup)

    private static let registrationLock = NSLock()

    public nonisolated func registerEncryptorSync<T: Encodable & Sendable>(
        for _: T.Type,
        wireName: String? = nil,
        targetEncryptedWireName: String? = nil,
        encryptor: @escaping @Sendable (T, CommonKeyManager, LabelResolver) async throws -> Data
    ) {
        let registryKey = wireName ?? String(describing: T.self)
        let expectedTypeName = String(describing: T.self)
        
        Self.registrationLock.lock()
        defer { Self.registrationLock.unlock() }
        
        // Store the encryptor closure
        wireNameToEncryptor[registryKey] = { [encryptor, expectedTypeName] value, keystore, resolver in
            guard let typedValue = value as? T else {
                throw SerializerError.typeMismatch("Expected \(expectedTypeName), got \(String(describing: Swift.type(of: value)))")
            }
            return try await encryptor(typedValue, keystore, resolver)
        }
        
        if let encryptedName = targetEncryptedWireName {
            encryptedWireByPlainWire[registryKey] = encryptedName
        }
    }

    public nonisolated func registerDecryptorSync<T: Decodable & Sendable>(
        for _: T.Type,
        wireName: String? = nil,
        decryptor: @escaping @Sendable (Data, CommonKeyManager) async throws -> T
    ) {
        let registryKey = wireName ?? String(describing: T.self)
        
        Self.registrationLock.lock()
        defer { Self.registrationLock.unlock() }
        
        wireNameToDecryptor[registryKey] = { [decryptor] data, keystore in
            try await decryptor(data, keystore)
        }
    }

    public nonisolated func registerDecoderSync(
        for wireName: String,
        decoder: @escaping @Sendable (Data) throws -> (any Decodable & Sendable)
    ) {
        Self.registrationLock.lock()
        defer { Self.registrationLock.unlock() }
        
        wireNameToDecoder[wireName] = { [decoder] data in
            try decoder(data)
        }
    }

    public nonisolated func registerWireNameSync<T>(for _: T.Type, wireName: String) {
        let swiftName = String(describing: T.self)
        
        Self.registrationLock.lock()
        defer { Self.registrationLock.unlock() }
        
        swiftTypeToWireName[swiftName] = wireName
        wireNameToSwiftType[wireName] = T.self
        wireNameCache.setObject(NSString(string: wireName), forKey: NSString(string: swiftName))
    }

    // MARK: - Registry Introspection

    public func allWireNames() -> [String] {
        Array(wireNameToSwiftType.keys)
    }

    public func isRegistered(wireName: String) -> Bool {
        wireNameToSwiftType[wireName] != nil
    }

    public func clearAll() {
        swiftTypeToWireName.removeAll()
        wireNameToSwiftType.removeAll()
        encryptedWireByPlainWire.removeAll()
        wireNameToDecryptor.removeAll()
        wireNameToEncryptor.removeAll()
        wireNameToDecoder.removeAll()
        wireNameToJsonConverter.removeAll()
        wireNameCache.removeAllObjects()
    }
}

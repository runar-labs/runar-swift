import Foundation
import SwiftCBOR
import SwiftFFI

// Note: Macro declarations are now in the swift-serializer-macros package
// and imported via the package dependency

// MARK: - Encryption Protocols

/// Protocol for types that can be encrypted
public protocol RunarEncryptable {
    associatedtype Encrypted: RunarDecryptable where Encrypted.Decrypted == Self
    func encryptWithKeystore(_ keystore: CommonKeyManager, resolver: LabelResolver) async throws -> Encrypted
}

/// Protocol for types that can be decrypted
public protocol RunarDecryptable {
    associatedtype Decrypted: RunarEncryptable where Decrypted.Encrypted == Self
    func decryptWithKeystore(_ keystore: CommonKeyManager) async throws -> Decrypted
}

/// Error types for serialization operations
public enum SerializerError: Error, LocalizedError {
    case deserializationFailed(String)
    case encryptionFailed(String)
    case typeMismatch(String)
    case invalidCategory(UInt8)
    case emptyData
    case typeNameTooLong(String)
    case serializationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .deserializationFailed(message):
            "Deserialization failed: \(message)"
        case let .encryptionFailed(message):
            "Encryption failed: \(message)"
        case let .typeMismatch(message):
            "Type mismatch: \(message)"
        case let .invalidCategory(category):
            "Invalid category: \(category)"
        case .emptyData:
            "Empty data"
        case let .typeNameTooLong(typeName):
            "Type name too long: \(typeName)"
        case let .serializationFailed(message):
            "Serialization failed: \(message)"
        }
    }
}

/// Categories for different value types, matching Rust implementation
public enum ValueCategory: UInt8, CaseIterable, Sendable {
    case null = 0
    case primitive = 1
    case list = 2
    case map = 3
    case `struct` = 4
    case bytes = 5
    case json = 6

    /// Create category from raw value
    public static func from(_ value: UInt8) -> ValueCategory? {
        ValueCategory(rawValue: value)
    }
}

/// Protocol for type-erased values
public protocol AnyValueProtocol: AnyObject {
    var typeName: String { get }
    var category: ValueCategory { get }
    func serialize(context: SerializationContext?) throws -> Data
    func asType<T>() -> T?
}

/// Type-erased box for storing values
private final class AnyValueBox: @unchecked Sendable {
    let typeName: String
    let category: ValueCategory
    private let rawValue: Any // @unchecked Sendable - Any is not Sendable but we handle it safely
    private let serializeFn: @Sendable (SerializationContext?) async throws -> Data
    private let asTypeFn: @Sendable (Any.Type) -> Any?

    init(
        value: some Any,
        typeName: String,
        category: ValueCategory,
        serializeFn: @escaping @Sendable (SerializationContext?) async throws -> Data,
        asTypeFn: @escaping @Sendable (Any.Type) -> Any?
    ) {
        rawValue = value
        self.typeName = typeName
        self.category = category
        self.serializeFn = serializeFn
        self.asTypeFn = asTypeFn
    }

    func serialize(context: SerializationContext?) async throws -> Data {
        try await serializeFn(context)
    }

    func asType<T>() -> T? {
        asTypeFn(T.self) as? T
    }

    /// Get the raw value for registry operations
    func getRawValue() -> Any {
        rawValue
    }
}

/// Main container type for zero-copy data handling
///
/// This class is now truly Sendable with no mutable state.
///
/// The materializedValue cache has been removed to eliminate @unchecked Sendable.
/// AnyValue is designed as a transfer container - extract values once and use
/// concrete types for repeated access.
public final class AnyValue: Sendable {
    private let box: AnyValueBox
    public let category: ValueCategory

    // Lazy deserialization support (immutable)
    private let lazyData: LazyData?

    /// Create a null value
    public static func null() -> AnyValue {
        AnyValue(category: .null, typeName: "null")
    }

    /// Check if this is a null value
    public var isNull: Bool {
        category == .null
    }

    /// Create a primitive value
    public static func primitive<T: CBOREncodable & Sendable>(_ value: T) -> AnyValue {
        let typeName = WireNames.primitiveWireName(T.self) ?? String(describing: T.self)
        let serializeFn: @Sendable (SerializationContext?) async throws -> Data = { _ in
            // Use SwiftCBOR for binary compatibility with Rust
            Data(value.encode(options: CBOROptions()))
        }

        let asTypeFn: @Sendable (Any.Type) -> Any? = { targetType in
            if targetType == T.self {
                return value
            }
            return nil
        }

        let box = AnyValueBox(
            value: value,
            typeName: typeName,
            category: .primitive,
            serializeFn: serializeFn,
            asTypeFn: asTypeFn
        )

        return AnyValue(box: box, category: .primitive)
    }

    /// Create a bytes value
    public static func bytes(_ data: Data) -> AnyValue {
        let typeName = "bytes"
        let serializeFn: @Sendable (SerializationContext?) async throws -> Data = { _ in
            // Raw payload for bytes category to match Rust
            data
        }

        let asTypeFn: @Sendable (Any.Type) -> Any? = { targetType in
            if targetType == Data.self {
                return data
            }
            return nil
        }

        let box = AnyValueBox(
            value: data as AnyObject,
            typeName: typeName,
            category: .bytes,
            serializeFn: serializeFn,
            asTypeFn: asTypeFn
        )

        return AnyValue(box: box, category: .bytes)
    }

    /// Create a struct value
    public static func `struct`<T: Codable & Sendable>(_ value: T) -> AnyValue {
        let swiftName = String(describing: T.self)
        let typeName = WireNames.primitiveWireName(T.self) ?? swiftName
        let serializeFn: @Sendable (SerializationContext?) async throws -> Data = { _ in
            // Use CBOR encoding directly for structs
            let encoder = CodableCBOREncoder()
            return try encoder.encode(value)
        }

        let asTypeFn: @Sendable (Any.Type) -> Any? = { targetType in
            if targetType == T.self {
                return value
            }
            return nil
        }

        let box = AnyValueBox(
            value: value,
            typeName: typeName,
            category: .struct,
            serializeFn: serializeFn,
            asTypeFn: asTypeFn
        )
        return AnyValue(box: box, category: .struct)
    }

    /// Create a list value (array of AnyValue)
    public static func list(_ values: [AnyValue]) -> AnyValue {
        let typeName = "list<any>"
        let serializeFn: @Sendable (SerializationContext?) async throws -> Data = { context in
            // CBOR array of element maps: {category:u8, typename:string, value:bytes}
            var cborElements: [CBOR] = []
            for value in values {
                let full = try await value.serialize(context: context)
                let header = try Self.parseSerializedHeader(full)
                let cat = header.category
                let name = header.wireName
                let payload = header.payload
                var map: [CBOR: CBOR] = [:]
                map[.utf8String("category")] = .unsignedInt(UInt64(cat.rawValue))
                map[.utf8String("typename")] = .utf8String(name)
                map[.utf8String("value")] = .byteString([UInt8](payload))
                cborElements.append(.map(map))
            }
            return Data(CBOR.array(cborElements).encode())
        }

        let asTypeFn: @Sendable (Any.Type) -> Any? = { targetType in
            if targetType == [AnyValue].self {
                return values
            }
            return nil
        }

        let box = AnyValueBox(
            value: values,
            typeName: typeName,
            category: .list,
            serializeFn: serializeFn,
            asTypeFn: asTypeFn
        )

        return AnyValue(box: box, category: .list)
    }

    /// Create a typed list value (array of Codable T), encoded as CBOR
    public static func listTyped<T: Codable & Sendable>(_ values: [T]) -> AnyValue {
        let typeName = WireNames.listWireName(T.self)

        let serializeFn: @Sendable (SerializationContext?) async throws -> Data = { _ in
            let encoder = CodableCBOREncoder()
            return try encoder.encode(values)
        }

        let asTypeFn: @Sendable (Any.Type) -> Any? = { targetType in
            if targetType == [T].self {
                return values
            }
            return nil
        }

        let box = AnyValueBox(
            value: values,
            typeName: typeName,
            category: .list,
            serializeFn: serializeFn,
            asTypeFn: asTypeFn
        )

        return AnyValue(box: box, category: .list)
    }

    /// Create a map value (dictionary of String to AnyValue)
    public static func map(_ values: [String: AnyValue]) -> AnyValue {
        let typeName = "map<string,any>"
        let serializeFn: @Sendable (SerializationContext?) async throws -> Data = { context in
            // CBOR map of key -> {category, typename, value}
            var cborMap: [CBOR: CBOR] = [:]
            for (key, value) in values {
                let full = try await value.serialize(context: context)
                let header = try Self.parseSerializedHeader(full)
                let cat = header.category
                let name = header.wireName
                let payload = header.payload
                var map: [CBOR: CBOR] = [:]
                map[.utf8String("category")] = .unsignedInt(UInt64(cat.rawValue))
                map[.utf8String("typename")] = .utf8String(name)
                map[.utf8String("value")] = .byteString([UInt8](payload))
                cborMap[.utf8String(key)] = .map(map)
            }
            return Data(CBOR.map(cborMap).encode())
        }

        let asTypeFn: @Sendable (Any.Type) -> Any? = { targetType in
            if targetType == [String: AnyValue].self {
                return values
            }
            return nil
        }

        let box = AnyValueBox(
            value: values,
            typeName: typeName,
            category: .map,
            serializeFn: serializeFn,
            asTypeFn: asTypeFn
        )

        return AnyValue(box: box, category: .map)
    }

    /// Create a typed map value (dictionary of String to Codable T), encoded as CBOR
    public static func mapTyped<T: Codable & Sendable>(_ values: [String: T]) -> AnyValue {
        let typeName = WireNames.mapWireName(T.self)

        let serializeFn: @Sendable (SerializationContext?) async throws -> Data = { _ in
            let encoder = CodableCBOREncoder()
            return try encoder.encode(values)
        }

        let asTypeFn: @Sendable (Any.Type) -> Any? = { targetType in
            if targetType == [String: T].self {
                return values
            }
            return nil
        }

        let box = AnyValueBox(
            value: values,
            typeName: typeName,
            category: .map,
            serializeFn: serializeFn,
            asTypeFn: asTypeFn
        )

        return AnyValue(box: box, category: .map)
    }

    /// Create a JSON value (JSON string as Data)
    public static func json(_ jsonData: Data) -> AnyValue {
        let typeName = "json"
        let serializeFn: @Sendable (SerializationContext?) async throws -> Data = { _ in
            // Encode JSON value to CBOR (mirror serde_json::Value)
            let obj = try JSONSerialization.jsonObject(with: jsonData)
            return try Data(encodeToCBOR(obj))
        }

        let asTypeFn: @Sendable (Any.Type) -> Any? = { targetType in
            if targetType == Data.self {
                return jsonData
            }
            if targetType == String.self {
                return String(data: jsonData, encoding: .utf8)
            }
            return nil
        }

        let box = AnyValueBox(
            value: jsonData,
            typeName: typeName,
            category: .json,
            serializeFn: serializeFn,
            asTypeFn: asTypeFn
        )

        return AnyValue(box: box, category: .json)
    }

    /// Create a lazy value for deferred deserialization
    public static func lazy(category: ValueCategory, lazyData: LazyData) -> AnyValue {
        let box = AnyValueBox(
            value: lazyData,
            typeName: lazyData.typeName,
            category: category,
            serializeFn: { @Sendable _ in
                // Return the original serialized data
                lazyData.data
            },
            asTypeFn: { @Sendable _ in nil } // Will be handled by lazy deserialization
        )

        return AnyValue(box: box, category: category, lazyData: lazyData)
    }

    /// Private initializer
    private init(box: AnyValueBox, category: ValueCategory, lazyData: LazyData? = nil) {
        self.box = box
        self.category = category
        self.lazyData = lazyData
    }

    /// Private initializer for null values
    private init(category: ValueCategory, typeName: String) {
        let serializeFn: @Sendable (SerializationContext?) async throws -> Data = { _ in
            Data()
        }

        let asTypeFn: @Sendable (Any.Type) -> Any? = { _ in
            nil
        }

        let box = AnyValueBox(
            value: NSObject(),
            typeName: typeName,
            category: category,
            serializeFn: serializeFn,
            asTypeFn: asTypeFn
        )

        self.box = box
        self.category = category
        lazyData = nil // ✅ Initialize lazyData as nil for null values
    }

    /// Get the type name of the contained value
    public var typeName: String {
        box.typeName
    }

    /// Serialize the value
    public func serialize(context: SerializationContext? = nil) async throws -> Data {
        if isNull {
            return Data([0]) // Single byte for null
        }

        let plainWireName = box.typeName
        let categoryByte = category.rawValue

        var buf = Data()
        buf.append(categoryByte)

        // Decide header wire name: prefer encrypted wire when using registry encryptor
        var headerWireName = plainWireName
        if context != nil, let encWire = await SerializationRegistry.shared.encryptedWireName(for: plainWireName) {
            headerWireName = encWire
        }

        let typeNameBytes = headerWireName.data(using: .utf8)!
        if typeNameBytes.count > 255 {
            throw SerializerError.typeNameTooLong(headerWireName)
        }

        if let context, category == .struct {
            // Registry-first encryption path for struct types
            guard let encryptor = await SerializationRegistry.shared.encryptor(for: plainWireName) else {
                throw SerializerError.serializationFailed("Missing encryptor for \(plainWireName)")
            }

            guard await SerializationRegistry.shared.encryptedWireName(for: plainWireName) != nil else {
                throw SerializerError.serializationFailed("Missing encrypted wire name for \(plainWireName)")
            }

            // Get the original value from the box for encryption
            let rawValue = box.getRawValue()

            // Produce payload using registry encryptor
            let payload = try await encryptor(rawValue, context.keystore, context.resolver)

            let isEncryptedByte: UInt8 = 0x01
            buf.append(isEncryptedByte)
            buf.append(UInt8(typeNameBytes.count))
            buf.append(typeNameBytes)
            buf.append(payload)
            return buf
        } else {
            // Plain serialization
            let bytes = try await box.serialize(context: nil)
            let isEncryptedByte: UInt8 = 0x00
            buf.append(isEncryptedByte)
            buf.append(UInt8(typeNameBytes.count))
            buf.append(typeNameBytes)
            buf.append(bytes)
        }

        return buf
    }

    /// Get the value as a specific type
    public func asType<T>(keystore: CommonKeyManager? = nil) async throws -> T {
        // Try to get from box (for already loaded values)
        if let result = box.asType() as T? {
            return result
        }

        // Try lazy deserialization
        if let lazyData {
            let value: T = try await deserializeLazyData(lazyData, to: T.self, keystore: keystore)
            return value
        }

        throw SerializerError.typeMismatch("Cannot get value as \(T.self)")
    }

    /// Convenience: get encrypted form of a plain type stored in this AnyValue
    /// by first materializing the plain value and then applying field-group encryption.
    public func asEncrypted<T: RunarEncryptable>(_: T.Type, keystore: CommonKeyManager, resolver: LabelResolver) async throws -> T.Encrypted {
        let plain: T = try await asType(keystore: keystore)
        return try await plain.encryptWithKeystore(keystore, resolver: resolver)
    }

    /// Deserialize lazy data into a concrete value of target type
    private func deserializeLazyData<T>(_ lazyData: LazyData, to _: T.Type, keystore: CommonKeyManager? = nil) async throws -> T {
        // Handle encrypted data using registry decryptor
        if lazyData.encrypted {
            // For encrypted data, use the registry decryptor to decrypt the encrypted struct
            guard let keystore else {
                throw SerializerError.deserializationFailed("No keystore provided for encrypted data")
            }

            // Try to find a registered decryptor for this wire name
            if let decryptor = await SerializationRegistry.shared.decryptor(for: lazyData.typeName) {
                let result = try await decryptor(lazyData.data, keystore)
                guard let casted = result as? T else {
                    throw SerializerError.typeMismatch("Cannot cast decrypted result to \(T.self)")
                }
                return casted
            } else {
                throw SerializerError.deserializationFailed("No decryptor registered for encrypted wire name: \(lazyData.typeName)")
            }
        }

        // Handle by strict wire names for known categories and primitives
        switch lazyData.typeName {
        case "bytes":
            // Rust ArcValue encodes raw bytes for the bytes category; accept raw payload
            guard let casted = Data(lazyData.data) as? T else { throw SerializerError.typeMismatch("Cannot cast bytes to \(T.self)") }
            return casted

        case "string":
            let bytes = Array(lazyData.data)
            if let cbor = try? CBOR.decode(bytes) {
                switch cbor {
                case let .utf8String(stringValue):
                    guard let casted = stringValue as? T else { 
                        throw SerializerError.typeMismatch("Cannot cast string to \(T.self)") 
                    }
                    return casted
                case let .array(arr) where arr.count == 1:
                    guard case let .utf8String(stringValue) = arr[0] else { break }
                    guard let casted = stringValue as? T else { 
                        throw SerializerError.typeMismatch("Cannot cast string to \(T.self)") 
                    }
                    return casted
                default: break
                }
            }
            do {
                let stringValue = try SwiftCBOR.CodableCBORDecoder().decode(String.self, from: Data(lazyData.data))
                guard let casted = stringValue as? T else { throw SerializerError.typeMismatch("Cannot cast string to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode String from CBOR: \(error)")
            }

        case "char":
            do {
                let stringValue = try SwiftCBOR.CodableCBORDecoder().decode(String.self, from: Data(lazyData.data))
                guard stringValue.count == 1, let characterValue = stringValue.first else { throw SerializerError.deserializationFailed("Invalid CBOR format for char") }
                guard let casted = characterValue as? T else { throw SerializerError.typeMismatch("Cannot cast char to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode char from CBOR: \(error)")
            }

        case "i8":
            do {
                let int8Value = try SwiftCBOR.CodableCBORDecoder().decode(Int8.self, from: Data(lazyData.data))
                guard let casted = int8Value as? T else { 
                    throw SerializerError.typeMismatch("Cannot cast i8 to \(T.self)") 
                }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode i8 from CBOR: \(error)")
            }

        case "i16":
            do {
                let int16Value = try SwiftCBOR.CodableCBORDecoder().decode(Int16.self, from: Data(lazyData.data))
                guard let casted = int16Value as? T else { 
                    throw SerializerError.typeMismatch("Cannot cast i16 to \(T.self)") 
                }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode i16 from CBOR: \(error)")
            }

        case "i32":
            do {
                let int32Value = try SwiftCBOR.CodableCBORDecoder().decode(Int32.self, from: Data(lazyData.data))
                guard let casted = int32Value as? T else { 
                    throw SerializerError.typeMismatch("Cannot cast i32 to \(T.self)") 
                }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode i32 from CBOR: \(error)")
            }

        case "i64":
            let bytes = Array(lazyData.data)
            if let cbor = try? CBOR.decode(bytes) {
                switch cbor {
                case let .unsignedInt(unsignedValue):
                    let int64Value = Int64(unsignedValue)
                    if let casted = int64Value as? T { return casted }
                    if let casted = Int(exactly: int64Value) as? T { return casted }
                    throw SerializerError.typeMismatch("Cannot cast i64 to \(T.self)")
                case let .negativeInt(negativeValue):
                    let int64Value = -Int64(negativeValue) - 1
                    if let casted = int64Value as? T { return casted }
                    if let casted = Int(exactly: int64Value) as? T { return casted }
                    throw SerializerError.typeMismatch("Cannot cast i64 to \(T.self)")
                case let .array(arr) where arr.count == 1:
                    if case let .unsignedInt(unsignedValue) = arr[0] {
                        let int64Value = Int64(unsignedValue)
                        if let casted = int64Value as? T { return casted }
                        if let casted = Int(exactly: int64Value) as? T { return casted }
                    } else if case let .negativeInt(negativeValue) = arr[0] {
                        let int64Value = -Int64(negativeValue) - 1
                        if let casted = int64Value as? T { return casted }
                        if let casted = Int(exactly: int64Value) as? T { return casted }
                    }
                // fallthrough to fallback
                default:
                    break
                }
            }
            do {
                let int64Value = try SwiftCBOR.CodableCBORDecoder().decode(Int64.self, from: Data(lazyData.data))
                if let casted = int64Value as? T { return casted }
                if let casted = Int(exactly: int64Value) as? T { return casted }
                throw SerializerError.typeMismatch("Cannot cast i64 to \(T.self)")
            } catch {
                throw SerializerError.deserializationFailed("Invalid CBOR format for i64")
            }

        case "u8":
            do {
                let uint8Value = try SwiftCBOR.CodableCBORDecoder().decode(UInt8.self, from: Data(lazyData.data))
                guard let casted = uint8Value as? T else { 
                    throw SerializerError.typeMismatch("Cannot cast u8 to \(T.self)") 
                }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode u8 from CBOR: \(error)")
            }

        case "u16":
            do {
                let uint16Value = try SwiftCBOR.CodableCBORDecoder().decode(UInt16.self, from: Data(lazyData.data))
                guard let casted = uint16Value as? T else { throw SerializerError.typeMismatch("Cannot cast u16 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode u16 from CBOR: \(error)")
            }

        case "u32":
            do {
                let uint32Value = try SwiftCBOR.CodableCBORDecoder().decode(UInt32.self, from: Data(lazyData.data))
                guard let casted = uint32Value as? T else { throw SerializerError.typeMismatch("Cannot cast u32 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode u32 from CBOR: \(error)")
            }

        case "u64":
            let bytesU = Array(lazyData.data)
            if let cbor = try? CBOR.decode(bytesU) {
                switch cbor {
                case let .unsignedInt(unsignedValue):
                    let uint64Value = UInt64(unsignedValue)
                    if let casted = uint64Value as? T { return casted }
                    if let casted = UInt(exactly: uint64Value) as? T { return casted }
                    throw SerializerError.typeMismatch("Cannot cast u64 to \(T.self)")
                case let .array(arr) where arr.count == 1:
                    if case let .unsignedInt(unsignedValue) = arr[0] {
                        let uint64Value = UInt64(unsignedValue)
                        if let casted = uint64Value as? T { return casted }
                        if let casted = UInt(exactly: uint64Value) as? T { return casted }
                    }
                default:
                    break
                }
            }
            do {
                let uint64Value = try SwiftCBOR.CodableCBORDecoder().decode(UInt64.self, from: Data(lazyData.data))
                if let casted = uint64Value as? T { return casted }
                if let casted = UInt(exactly: uint64Value) as? T { return casted }
                throw SerializerError.typeMismatch("Cannot cast u64 to \(T.self)")
            } catch {
                throw SerializerError.deserializationFailed("Invalid CBOR format for u64")
            }

        case "f32":
            do {
                let floatValue = try SwiftCBOR.CodableCBORDecoder().decode(Float.self, from: Data(lazyData.data))
                guard let casted = floatValue as? T else { 
                    throw SerializerError.typeMismatch("Cannot cast f32 to \(T.self)") 
                }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode f32 from CBOR: \(error)")
            }

        case "f64":
            do {
                let doubleValue = try SwiftCBOR.CodableCBORDecoder().decode(Double.self, from: Data(lazyData.data))
                guard let casted = doubleValue as? T else { 
                    throw SerializerError.typeMismatch("Cannot cast f64 to \(T.self)") 
                }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode f64 from CBOR: \(error)")
            }

        case "bool":
            do {
                let boolValue = try SwiftCBOR.CodableCBORDecoder().decode(Bool.self, from: Data(lazyData.data))
                guard let casted = boolValue as? T else { 
                    throw SerializerError.typeMismatch("Cannot cast bool to \(T.self)") 
                }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode Bool from CBOR: \(error)")
            }

        case "json":
            // Decode CBOR-encoded JSON value and return requested representation
            let cborData = Array(lazyData.data)
            guard let cbor = try? CBOR.decode(cborData) else {
                throw SerializerError.deserializationFailed("Invalid CBOR for json")
            }
            let foundationObject = try cborToFoundationJSON(cbor)
            if T.self == Data.self {
                let data = try JSONSerialization.data(withJSONObject: foundationObject, options: [])
                guard let casted = data as? T else {
                    throw SerializerError.typeMismatch("Cannot cast JSON data to \(T.self)")
                }
                return casted
            }
            if T.self == String.self {
                let data = try JSONSerialization.data(withJSONObject: foundationObject, options: [])
                guard let str = String(data: data, encoding: .utf8) else {
                    throw SerializerError.deserializationFailed("Failed to re-encode JSON to UTF-8 string")
                }
                guard let casted = str as? T else {
                    throw SerializerError.typeMismatch("Cannot cast JSON string to \(T.self)")
                }
                return casted
            }
            guard let casted = foundationObject as? T else {
                throw SerializerError.typeMismatch("Cannot cast JSON object to \(T.self)")
            }
            return casted

        case "list<any>":
            // CBOR array of element maps (Rust serde format) or a direct array of maps
            let cborData = Array(lazyData.data)
            guard let cbor = try? CBOR.decode(cborData) else {
                throw SerializerError.deserializationFailed("Invalid CBOR for list<any>")
            }
            guard case let .array(elements) = cbor else {
                throw SerializerError.deserializationFailed("Expected CBOR array for list<any>")
            }
            var out: [AnyValue] = []
            for element in elements {
                guard case let .map(map) = element else { 
                    throw SerializerError.deserializationFailed("Invalid element in list<any>") 
                }
                guard let catEntry = map[.utf8String("category")], 
                      let nameEntry = map[.utf8String("typename")], 
                      let valEntry = map[.utf8String("value")] else {
                    throw SerializerError.deserializationFailed("Missing fields in list<any> element")
                }
                let cat: ValueCategory
                switch catEntry {
                case let .unsignedInt(unsignedValue):
                    guard let category = ValueCategory.from(UInt8(unsignedValue)) else { 
                        throw SerializerError.deserializationFailed("Bad category") 
                    }
                    cat = category
                default: throw SerializerError.deserializationFailed("Bad category type")
                }
                let name: String
                switch nameEntry { 
                    case let .utf8String(stringValue): name = stringValue
                    default: throw SerializerError.deserializationFailed("Bad typename type") 
                }
                let payload: Data
                switch valEntry {
                case let .byteString(bytesValue):
                    payload = Data(bytesValue)
                case let .array(arr):
                    var bytes: [UInt8] = []
                    bytes.reserveCapacity(arr.count)
                    var isValid = true
                    for element in arr {
                        if case let .unsignedInt(unsignedValue) = element, unsignedValue <= UInt64(UInt8.max) {
                            bytes.append(UInt8(unsignedValue))
                        } else {
                            isValid = false; break
                        }
                    }
                    if isValid {
                        payload = Data(bytes)
                    } else {
                        payload = Data(valEntry.encode())
                    }
                default:
                    // If the value is itself a CBOR structure, re-encode it to bytes (Rust may store raw CBOR of inner payload)
                    payload = Data(valEntry.encode())
                }
                let child = AnyValue.lazy(category: cat, lazyData: LazyData(typeName: name, data: payload, encrypted: false))
                out.append(child)
            }
            guard let casted = out as? T else { throw SerializerError.typeMismatch("Cannot cast list<any> to \(T.self)") }
            return casted

        case "map<string,any>":
            // CBOR map of key -> element map (Rust serde format)
            let cborData = Array(lazyData.data)
            guard let cbor = try? CBOR.decode(cborData) else {
                throw SerializerError.deserializationFailed("Invalid CBOR for map<string,any>")
            }
            guard case let .map(entries) = cbor else {
                throw SerializerError.deserializationFailed("Expected CBOR map for map<string,any>")
            }
            var out: [String: AnyValue] = [:]
            for (keyEntry, valueEntry) in entries {
                guard case let .utf8String(key) = keyEntry, case let .map(map) = valueEntry else {
                    throw SerializerError.deserializationFailed("Invalid entry in map<string,any>")
                }
                guard let catEntry = map[.utf8String("category")], let nameEntry = map[.utf8String("typename")], let valEntry = map[.utf8String("value")] else {
                    throw SerializerError.deserializationFailed("Missing fields in map<string,any> element")
                }
                let cat: ValueCategory
                switch catEntry {
                case let .unsignedInt(unsignedValue):
                    guard let category = ValueCategory.from(UInt8(unsignedValue)) else { 
                        throw SerializerError.deserializationFailed("Bad category") 
                    }
                    cat = category
                default: throw SerializerError.deserializationFailed("Bad category type")
                }
                let name: String
                switch nameEntry { 
                    case let .utf8String(stringValue): name = stringValue
                    default: throw SerializerError.deserializationFailed("Bad typename type") 
                }
                let payload: Data
                switch valEntry {
                case let .byteString(bytesValue): payload = Data(bytesValue)
                case let .array(arr):
                    var bytes: [UInt8] = []
                    bytes.reserveCapacity(arr.count)
                    var isValid = true
                    for element in arr {
                        if case let .unsignedInt(unsignedValue) = element, unsignedValue <= UInt64(UInt8.max) {
                            bytes.append(UInt8(unsignedValue))
                        } else {
                            isValid = false; break
                        }
                    }
                    if isValid {
                        payload = Data(bytes)
                    } else {
                        payload = Data(valEntry.encode())
                    }
                default: payload = Data(valEntry.encode())
                }
                let child = AnyValue.lazy(category: cat, lazyData: LazyData(typeName: name, data: payload, encrypted: false))
                out[key] = child
            }
            guard let casted = out as? T else { throw SerializerError.typeMismatch("Cannot cast map<string,any> to \(T.self)") }
            return casted

        default:
            // Typed containers: list<ElemWire> or map<string,ElemWire>
            if WireNameParser.parseList(lazyData.typeName) != nil, lazyData.typeName != "list<any>" {
                // Decode as plain typed CBOR array to Decodable target
                let cborData = Array(lazyData.data)
                guard let target = T.self as? Decodable.Type else {
                    throw SerializerError.deserializationFailed("Type \(T.self) is not Decodable")
                }
                guard let decodedAny = try? SwiftCBOR.CodableCBORDecoder().decode(target, from: Data(cborData)) as? T else {
                    throw SerializerError.deserializationFailed("Typed list decode failed")
                }
                return decodedAny
            }

            if WireNameParser.parseMap(lazyData.typeName) != nil, lazyData.typeName != "map<string,any>" {
                let cborData = Array(lazyData.data)
                // Try plain typed map decode to Decodable
                guard let target = T.self as? Decodable.Type else {
                    throw SerializerError.deserializationFailed("Type \(T.self) is not Decodable")
                }
                guard let decodedAny = try? SwiftCBOR.CodableCBORDecoder().decode(target, from: Data(cborData)) as? T else {
                    throw SerializerError.deserializationFailed("Typed map decode failed")
                }
                return decodedAny
            }

            // Structs and custom types: require known wire name in registry
            // Try to find a registered decoder for this wire name
            if let decoder = await SerializationRegistry.shared.decoder(for: lazyData.typeName) {
                let result = try decoder(lazyData.data)

                // If decoder returns the expected type, return it
                if let typedResult = result as? T {
                    return typedResult
                }

                // If decoder returns an encrypted value but T is the plain type, decrypt with keystore
                if let keystore, let encryptedValue = result as? AnyRunarDecryptable {
                    guard let decrypted = try? await encryptedValue.runarDecryptWithKeystore(keystore) as? T else {
                        throw SerializerError.typeMismatch("Failed to decrypt value to \(T.self)")
                    }
                    return decrypted
                }

                // If T is an Encrypted type, allow direct cast
                if T.self is AnyRunarDecryptable.Type, let encrypted = result as? T {
                    return encrypted
                }

                throw SerializerError.typeMismatch("Decoder returned incompatible type for \(T.self)")
            }

            // No decoder found for this wire name - fall back to plain CBOR deserialization
            if let target = T.self as? Decodable.Type {
                guard let result = try SwiftCBOR.CodableCBORDecoder().decode(target, from: lazyData.data) as? T else {
                    throw SerializerError.deserializationFailed("Failed to cast decoded result to \(T.self)")
                }
                return result
            } else {
                throw SerializerError.deserializationFailed("Type \(T.self) is not Decodable and not registered in registry")
            }
        }
    }

    // Parse our header: [category][encrypted][name_len][name_bytes][payload]
    private struct SerializedHeader {
        let category: ValueCategory
        let isEncrypted: Bool
        let wireName: String
        let payload: Data
    }
    
    private static func parseSerializedHeader(_ data: Data) throws -> SerializedHeader {
        guard !data.isEmpty else { throw SerializerError.emptyData }
        let categoryByte = data[0]
        guard let category = ValueCategory.from(categoryByte) else { throw SerializerError.invalidCategory(categoryByte) }
        guard data.count >= 3 else { throw SerializerError.deserializationFailed("Data too short for header") }
        let isEncrypted = data[1] == 0x01
        let nameLen = Int(data[2])
        guard data.count >= 3 + nameLen else { throw SerializerError.deserializationFailed("Data too short for type name") }
        let nameData = data[3 ..< (3 + nameLen)]
        guard let name = String(data: Data(nameData), encoding: .utf8) else { throw SerializerError.deserializationFailed("Invalid type name encoding") }
        let payload = data[(3 + nameLen)...]
        return SerializedHeader(category: category, isEncrypted: isEncrypted, wireName: name, payload: Data(payload))
    }

    /// Deserialize from data
    public static func deserialize(_ data: Data, keystore _: CommonKeyManager? = nil) throws -> AnyValue {
        guard !data.isEmpty else {
            throw SerializerError.emptyData
        }

        let categoryByte = data[0]
        guard let category = ValueCategory.from(categoryByte) else {
            throw SerializerError.invalidCategory(categoryByte)
        }

        if category == .null {
            return AnyValue.null()
        }

        // Parse the binary format: [category][encrypted][type_name_len][type_name][data]
        guard data.count >= 3 else {
            throw SerializerError.deserializationFailed("Data too short for non-null value")
        }

        let isEncryptedByte = data[1]
        let typeNameLen = Int(data[2])

        guard data.count >= 3 + typeNameLen else {
            throw SerializerError.deserializationFailed("Data too short for type name")
        }

        let typeNameData = data[3 ..< (3 + typeNameLen)]
        guard let typeName = String(data: Data(typeNameData), encoding: .utf8) else {
            throw SerializerError.deserializationFailed("Invalid type name encoding")
        }

        let dataStart = 3 + typeNameLen
        let valueData = data[dataStart...]
        let isEncrypted = isEncryptedByte == 0x01

        // Strict wire-name validation for primitives/containers/json
        switch category {
        case .primitive:
            if !WireNames.isValidPrimitiveWireName(typeName) {
                throw SerializerError.deserializationFailed("Unknown primitive wire name: \(typeName)")
            }
        case .list:
            if typeName != "list<any>", WireNameParser.parseList(typeName) == nil {
                throw SerializerError.deserializationFailed("Unknown list wire name: \(typeName)")
            }
        case .map:
            if typeName != "map<string,any>", WireNameParser.parseMap(typeName) == nil {
                throw SerializerError.deserializationFailed("Unknown map wire name: \(typeName)")
            }
        case .json:
            if typeName != "json" { 
                throw SerializerError.deserializationFailed("Unknown json wire name: \(typeName)") 
            }
        case .bytes:
            if typeName != "bytes" { 
                throw SerializerError.deserializationFailed("Unknown bytes wire name: \(typeName)") 
            }
        default:
            break
        }

        // Create lazy data for deferred deserialization
        let lazyData = LazyData(
            typeName: typeName,
            data: Data(valueData),
            encrypted: isEncrypted
        )

        // Keep everything lazy, including bytes and json
        return AnyValue.lazy(category: category, lazyData: lazyData)
    }

    // MARK: - JSON Output
}

/// CBOR encoding helper using SwiftCBOR
private func encodeToCBOR(_ value: Any) throws -> [UInt8] {
    switch value {
    case let dict as [String: Any]:
        // Encode as CBOR map
        var map: [CBOR: CBOR] = [:]
        for (key, val) in dict {
            let keyCBOR = CBOR.utf8String(key)
            let valueCBOR = try encodeToCBORValue(val)
            map[keyCBOR] = valueCBOR
        }
        return CBOR.map(map).encode()

    case let array as [Any]:
        // Encode as CBOR array
        let arrayCBOR = try array.map { try encodeToCBORValue($0) }
        return CBOR.array(arrayCBOR).encode()

    default:
        return try encodeToCBORValue(value).encode()
    }
}

/// Helper to convert Any to CBOR value using full SwiftCBOR capabilities
private func encodeToCBORValue(_ value: Any) throws -> CBOR {
    switch value {
    case let string as String:
        return CBOR.utf8String(string)

    case let int as Int:
        return int.toCBOR()

    case let int8 as Int8:
        return int8.toCBOR()

    case let int16 as Int16:
        return int16.toCBOR()

    case let int32 as Int32:
        return int32.toCBOR()

    case let int64 as Int64:
        return int64.toCBOR()

    case let uint as UInt:
        return uint.toCBOR()

    case let uint8 as UInt8:
        return uint8.toCBOR()

    case let uint16 as UInt16:
        return uint16.toCBOR()

    case let uint32 as UInt32:
        return uint32.toCBOR()

    case let uint64 as UInt64:
        return uint64.toCBOR()

    case let bool as Bool:
        return CBOR.boolean(bool)

    case let float as Float:
        return float.toCBOR()

    case let double as Double:
        return double.toCBOR()

    case let date as Date:
        return date.toCBOR()

    case let data as Data:
        return data.toCBOR()

    case let array as [String]:
        return array.toCBOR()

    case let array as [Int]:
        return array.toCBOR()

    case let array as [Double]:
        return array.toCBOR()

    case let array as [Bool]:
        return array.toCBOR()

    case let array as [Date]:
        return array.toCBOR()

    case let array as [Data]:
        return array.toCBOR()

    case let dict as [String: String]:
        return dict.toCBOR()

    case let dict as [String: Int]:
        return dict.toCBOR()

    case let dict as [String: Double]:
        return dict.toCBOR()

    case let dict as [String: Bool]:
        return dict.toCBOR()

    case let dict as [String: Date]:
        return dict.toCBOR()

    case let dict as [String: Data]:
        return dict.toCBOR()

    case let nsDict as NSDictionary:
        // Convert NSDictionary to CBOR map directly
        var map: [CBOR: CBOR] = [:]
        for (key, value) in nsDict {
            if let keyStr = key as? String {
                let keyCBOR = CBOR.utf8String(keyStr)
                let valueCBOR = try encodeToCBORValue(value)
                map[keyCBOR] = valueCBOR
            }
        }
        return CBOR.map(map)

    case is NSNull:
        return CBOR.null

    default:
        throw SerializerError.serializationFailed("Unsupported type for CBOR encoding: \(type(of: value))")
    }
}

/// Lazy data structure for deferred deserialization
public struct LazyData: Sendable {
    let typeName: String
    let data: Data
    let encrypted: Bool
}

/// Protocol for types that can be automatically serialized
public protocol PlainSerializable: Codable & Sendable {
    /// Convert this type to an AnyValue
    func toAnyValue() -> AnyValue

    /// Create this type from an AnyValue
    static func fromAnyValue(_ value: AnyValue) async throws -> Self
}

/// Default implementation for PlainSerializable
public extension PlainSerializable {
    func toAnyValue() -> AnyValue {
        AnyValue.struct(self)
    }

    static func fromAnyValue(_ value: AnyValue) async throws -> Self {
        try await value.asType()
    }
}

// (Removed legacy TypeRegistry; use SerializationRegistry instead)

// MARK: - Encryption Types

// No dummy keystore - all encryption must use real FFI implementation

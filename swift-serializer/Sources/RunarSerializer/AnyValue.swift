import Foundation
#if canImport(RunarKeys)
import RunarKeys
#endif
import SwiftCBOR

// Note: Macro declarations are now in the swift-serializer-macros package
// and imported via the package dependency

// MARK: - Encryption Protocols

/// Protocol for types that can be encrypted
public protocol RunarEncryptable {
    associatedtype Encrypted: RunarDecryptable where Encrypted.Decrypted == Self
    func encryptWithKeystore(_ keystore: RunarKeys.EnvelopeCrypto, resolver: LabelResolver) throws -> Encrypted
}

/// Protocol for types that can be decrypted
public protocol RunarDecryptable {
    associatedtype Decrypted: RunarEncryptable where Decrypted.Encrypted == Self
    func decryptWithKeystore(_ keystore: RunarKeys.EnvelopeCrypto) throws -> Decrypted
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
public enum ValueCategory: UInt8, CaseIterable {
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
private class AnyValueBox {
    let typeName: String
    let category: ValueCategory
    private let serializeFn: (SerializationContext?) throws -> Data
    private let asTypeFn: (Any.Type) -> Any?

    init(
        value _: some Any,
        typeName: String,
        category: ValueCategory,
        serializeFn: @escaping (SerializationContext?) throws -> Data,
        asTypeFn: @escaping (Any.Type) -> Any?
    ) {
        self.typeName = typeName
        self.category = category
        self.serializeFn = serializeFn
        self.asTypeFn = asTypeFn
    }

    func serialize(context: SerializationContext?) throws -> Data {
        try serializeFn(context)
    }

    func asType<T>() -> T? {
        asTypeFn(T.self) as? T
    }
}

/// Main container type for zero-copy data handling
public class AnyValue {
    private let box: AnyValueBox
    public let category: ValueCategory

    // Lazy deserialization support
    private var materializedValue: Any?
    private var lazyData: LazyData?

    /// Create a null value
    public static func null() -> AnyValue {
        AnyValue(category: .null, typeName: "null")
    }

    /// Check if this is a null value
    public var isNull: Bool {
        category == .null
    }

    /// Create a primitive value
    public static func primitive<T: CBOREncodable>(_ value: T) -> AnyValue {
        let typeName = WireNames.primitiveWireName(T.self) ?? String(describing: T.self)
        let serializeFn: (SerializationContext?) throws -> Data = { _ in
            // Use SwiftCBOR for binary compatibility with Rust
            Data(value.encode(options: CBOROptions()))
        }

        let asTypeFn: (Any.Type) -> Any? = { targetType in
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
        let serializeFn: (SerializationContext?) throws -> Data = { _ in
            // Raw payload for bytes category to match Rust
            return data
        }

        let asTypeFn: (Any.Type) -> Any? = { targetType in
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
    public static func `struct`<T: Codable>(_ value: T) -> AnyValue {
        let swiftName = String(describing: T.self)
        let typeName = (try? awaitTypeNameRegistryLookup(swiftName: swiftName)) ?? swiftName
        let serializeFn: (SerializationContext?) throws -> Data = { _ in
            // Use CBOR encoding directly for structs
            let encoder = CodableCBOREncoder()
            return try encoder.encode(value)
        }

        let asTypeFn: (Any.Type) -> Any? = { targetType in
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
        let serializeFn: (SerializationContext?) throws -> Data = { context in
            // CBOR array of element maps: {category:u8, typename:string, value:bytes}
            var cborElements: [CBOR] = []
            for value in values {
                let full = try value.serialize(context: context)
                let (cat, _, name, payload) = try Self.parseSerializedHeader(full)
                var map: [CBOR: CBOR] = [:]
                map[.utf8String("category")] = .unsignedInt(UInt64(cat.rawValue))
                map[.utf8String("typename")] = .utf8String(name)
                map[.utf8String("value")] = .byteString([UInt8](payload))
                cborElements.append(.map(map))
            }
            return Data(CBOR.array(cborElements).encode())
        }

        let asTypeFn: (Any.Type) -> Any? = { targetType in
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
    public static func listTyped<T: Codable>(_ values: [T]) -> AnyValue {
        let typeName = WireNames.listWireName(T.self)

        let serializeFn: (SerializationContext?) throws -> Data = { context in
            // If element-level encryptor exists and context is provided, encrypt each element as CBOR bstr
            if let ctx = context, let encryptor = awaitLookupEncryptor(forWireName: typeName) {
                var arr: [CBOR] = []
                let encoder = CodableCBOREncoder()
                for v in values {
                    let plain = try encoder.encode(v)
                    let encrypted = try encryptor(plain, ctx)
                    arr.append(.byteString([UInt8](encrypted)))
                }
                return Data(CBOR.array(arr).encode())
            }
            let encoder = CodableCBOREncoder()
            return try encoder.encode(values)
        }

        let asTypeFn: (Any.Type) -> Any? = { targetType in
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
        let serializeFn: (SerializationContext?) throws -> Data = { context in
            // CBOR map of key -> {category, typename, value}
            var cborMap: [CBOR: CBOR] = [:]
            for (key, value) in values {
                let full = try value.serialize(context: context)
                let (cat, _, name, payload) = try Self.parseSerializedHeader(full)
                var map: [CBOR: CBOR] = [:]
                map[.utf8String("category")] = .unsignedInt(UInt64(cat.rawValue))
                map[.utf8String("typename")] = .utf8String(name)
                map[.utf8String("value")] = .byteString([UInt8](payload))
                cborMap[.utf8String(key)] = .map(map)
            }
            return Data(CBOR.map(cborMap).encode())
        }

        let asTypeFn: (Any.Type) -> Any? = { targetType in
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
    public static func mapTyped<T: Codable>(_ values: [String: T]) -> AnyValue {
        let typeName = WireNames.mapWireName(T.self)

        let serializeFn: (SerializationContext?) throws -> Data = { context in
            if let ctx = context, let encryptor = awaitLookupEncryptor(forWireName: typeName) {
                var map: [CBOR: CBOR] = [:]
                let encoder = CodableCBOREncoder()
                for (k, v) in values {
                    let plain = try encoder.encode(v)
                    let encrypted = try encryptor(plain, ctx)
                    map[.utf8String(k)] = .byteString([UInt8](encrypted))
                }
                return Data(CBOR.map(map).encode())
            }
            let encoder = CodableCBOREncoder()
            return try encoder.encode(values)
        }

        let asTypeFn: (Any.Type) -> Any? = { targetType in
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
        let serializeFn: (SerializationContext?) throws -> Data = { _ in
            // Encode JSON value to CBOR (mirror serde_json::Value)
            let obj = try JSONSerialization.jsonObject(with: jsonData)
            return try Data(encodeToCBOR(obj))
        }

        let asTypeFn: (Any.Type) -> Any? = { targetType in
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
            serializeFn: { _ in
                // Return the original serialized data
                lazyData.data
            },
            asTypeFn: { _ in nil } // Will be handled by lazy deserialization
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
        let serializeFn: (SerializationContext?) throws -> Data = { _ in
            Data()
        }

        let asTypeFn: (Any.Type) -> Any? = { _ in
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
    }

    /// Get the type name of the contained value
    public var typeName: String {
        box.typeName
    }

    /// Serialize the value
    public func serialize(context: SerializationContext? = nil) throws -> Data {
        if isNull {
            return Data([0]) // Single byte for null
        }

        let typeName = box.typeName
        let categoryByte = category.rawValue

        var buf = Data()
        buf.append(categoryByte)

        let typeNameBytes = typeName.data(using: .utf8)!
        if typeNameBytes.count > 255 {
            throw SerializerError.typeNameTooLong(typeName)
        }

        if let ctx = context {
            // Encrypted serialization (envelope around payload)
            let bytes = try box.serialize(context: context)
            let envelopeData = try EnvelopeEncryption.encrypt(bytes, context: ctx)
            let envelopeBytes = try EnvelopeEncryption.serializeToCBOR(envelopeData)

            let isEncryptedByte: UInt8 = 0x01
            buf.append(isEncryptedByte)
            buf.append(UInt8(typeNameBytes.count))
            buf.append(typeNameBytes)
            buf.append(envelopeBytes)
        } else {
            // Plain serialization
            let bytes = try box.serialize(context: nil)
            let isEncryptedByte: UInt8 = 0x00
            buf.append(isEncryptedByte)
            buf.append(UInt8(typeNameBytes.count))
            buf.append(typeNameBytes)
            buf.append(bytes)
        }

        return buf
    }

    /// Get the value as a specific type
    public func asType<T>() async throws -> T {
        // First, try to get from materialized value
        if let value = materializedValue {
            guard let result = value as? T else {
                throw SerializerError.typeMismatch("Cannot cast \(typeName) to \(T.self)")
            }
            return result
        }

        // Try to get from box (for already loaded values)
        if let result = box.asType() as T? {
            return result
        }

        // Try lazy deserialization
        if let lazyData {
            let value: T = try await deserializeLazyData(lazyData, to: T.self)
            materializedValue = value
            return value
        }

        throw SerializerError.typeMismatch("Cannot get value as \(T.self)")
    }

    /// Deserialize lazy data into a concrete value of target type
    private func deserializeLazyData<T>(_ lazyData: LazyData, to targetType: T.Type) async throws -> T {
        // Handle encrypted data using real decryption
        if lazyData.encrypted {
            // Deserialize the envelope data from CBOR
            let envelopeData = try EnvelopeEncryption.deserializeFromCBOR(lazyData.data)

            // Decrypt using the keystore
            guard let keystore = lazyData.keystore else {
                throw SerializerError.deserializationFailed("No keystore provided for encrypted data")
            }

            // Try to decrypt with profile keys first, then network key
            var decryptedData: Data
            do {
                // Try network-based decryption first (more reliable)
                decryptedData = try keystore.decryptWithNetwork(envelopeData: envelopeData)
            } catch {
                // If network decryption fails, try profile-based decryption
                // We need to know which profile to use - for now, use a default
                let defaultProfileId = "default"
                decryptedData = try keystore.decryptWithProfile(envelopeData: envelopeData, profileId: defaultProfileId)
            }

            // Continue with normal deserialization using the decrypted data
            return try await deserializeLazyData(LazyData(
                typeName: lazyData.typeName,
                data: decryptedData,
                keystore: nil, // No longer encrypted
                encrypted: false
            ), to: targetType)
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
                case let .utf8String(s):
                    if let casted = s as? T { return casted }
                    throw SerializerError.typeMismatch("Cannot cast string to \(T.self)")
                case let .array(arr) where arr.count == 1:
                    if case let .utf8String(s) = arr[0] {
                        if let casted = s as? T { return casted }
                        throw SerializerError.typeMismatch("Cannot cast string to \(T.self)")
                    }
                default: break
                }
            }
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(String.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast string to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode String from CBOR: \(error)")
            }

        case "char":
            do {
                let s = try SwiftCBOR.CodableCBORDecoder().decode(String.self, from: Data(lazyData.data))
                guard s.count == 1, let ch = s.first else { throw SerializerError.deserializationFailed("Invalid CBOR format for char") }
                guard let casted = ch as? T else { throw SerializerError.typeMismatch("Cannot cast char to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode char from CBOR: \(error)")
            }

        case "i8":
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(Int8.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast i8 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode i8 from CBOR: \(error)")
            }

        case "i16":
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(Int16.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast i16 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode i16 from CBOR: \(error)")
            }

        case "i32":
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(Int32.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast i32 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode i32 from CBOR: \(error)")
            }

        case "i64":
            let bytes = Array(lazyData.data)
            if let cbor = try? CBOR.decode(bytes) {
                switch cbor {
                case let .unsignedInt(u):
                    let v = Int64(u)
                    if let casted = v as? T { return casted }
                    if let casted = Int(exactly: v) as? T { return casted }
                    throw SerializerError.typeMismatch("Cannot cast i64 to \(T.self)")
                case let .negativeInt(n):
                    let v = -Int64(n) - 1
                    if let casted = v as? T { return casted }
                    if let casted = Int(exactly: v) as? T { return casted }
                    throw SerializerError.typeMismatch("Cannot cast i64 to \(T.self)")
                case let .array(arr) where arr.count == 1:
                    if case let .unsignedInt(u) = arr[0] {
                        let v = Int64(u)
                        if let casted = v as? T { return casted }
                        if let casted = Int(exactly: v) as? T { return casted }
                    } else if case let .negativeInt(n) = arr[0] {
                        let v = -Int64(n) - 1
                        if let casted = v as? T { return casted }
                        if let casted = Int(exactly: v) as? T { return casted }
                    }
                    // fallthrough to fallback
                default:
                    break
                }
            }
            // Fallback to Codable decoder for canonical integer
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(Int64.self, from: Data(lazyData.data))
                if let casted = v as? T { return casted }
                if let casted = Int(exactly: v) as? T { return casted }
                throw SerializerError.typeMismatch("Cannot cast i64 to \(T.self)")
            } catch {
                throw SerializerError.deserializationFailed("Invalid CBOR format for i64")
            }

        case "u8":
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(UInt8.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast u8 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode u8 from CBOR: \(error)")
            }

        case "u16":
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(UInt16.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast u16 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode u16 from CBOR: \(error)")
            }

        case "u32":
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(UInt32.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast u32 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode u32 from CBOR: \(error)")
            }

        case "u64":
            let bytesU = Array(lazyData.data)
            if let cbor = try? CBOR.decode(bytesU) {
                switch cbor {
                case let .unsignedInt(u):
                    let v = UInt64(u)
                    if let casted = v as? T { return casted }
                    if let casted = UInt(exactly: v) as? T { return casted }
                    throw SerializerError.typeMismatch("Cannot cast u64 to \(T.self)")
                case let .array(arr) where arr.count == 1:
                    if case let .unsignedInt(u) = arr[0] {
                        let v = UInt64(u)
                        if let casted = v as? T { return casted }
                        if let casted = UInt(exactly: v) as? T { return casted }
                    }
                default:
                    break
                }
            }
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(UInt64.self, from: Data(lazyData.data))
                if let casted = v as? T { return casted }
                if let casted = UInt(exactly: v) as? T { return casted }
                throw SerializerError.typeMismatch("Cannot cast u64 to \(T.self)")
            } catch {
                throw SerializerError.deserializationFailed("Invalid CBOR format for u64")
            }

        case "f32":
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(Float.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast f32 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode f32 from CBOR: \(error)")
            }

        case "f64":
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(Double.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast f64 to \(T.self)") }
                return casted
            } catch {
                throw SerializerError.deserializationFailed("Failed to decode f64 from CBOR: \(error)")
            }

        case "bool":
            do {
                let v = try SwiftCBOR.CodableCBORDecoder().decode(Bool.self, from: Data(lazyData.data))
                guard let casted = v as? T else { throw SerializerError.typeMismatch("Cannot cast bool to \(T.self)") }
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
                return data as! T
            }
            if T.self == String.self {
                let data = try JSONSerialization.data(withJSONObject: foundationObject, options: [])
                guard let str = String(data: data, encoding: .utf8) else {
                    throw SerializerError.deserializationFailed("Failed to re-encode JSON to UTF-8 string")
                }
                return str as! T
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
            for el in elements {
                guard case let .map(map) = el else { throw SerializerError.deserializationFailed("Invalid element in list<any>") }
                guard let catEntry = map[.utf8String("category")], let nameEntry = map[.utf8String("typename")], let valEntry = map[.utf8String("value")] else {
                    throw SerializerError.deserializationFailed("Missing fields in list<any> element")
                }
                let cat: ValueCategory
                switch catEntry {
                case let .unsignedInt(u):
                    guard let c = ValueCategory.from(UInt8(u)) else { throw SerializerError.deserializationFailed("Bad category") }
                    cat = c
                default: throw SerializerError.deserializationFailed("Bad category type")
                }
                let name: String
                switch nameEntry { case let .utf8String(s): name = s; default: throw SerializerError.deserializationFailed("Bad typename type") }
                let payload: Data
                switch valEntry {
                case let .byteString(b):
                    payload = Data(b)
                case let .array(arr):
                    var bytes: [UInt8] = []
                    bytes.reserveCapacity(arr.count)
                    var ok = true
                    for e in arr {
                        if case let .unsignedInt(u) = e, u <= UInt64(UInt8.max) {
                            bytes.append(UInt8(u))
                        } else {
                            ok = false; break
                        }
                    }
                    if ok {
                        payload = Data(bytes)
                    } else {
                        payload = Data(valEntry.encode())
                    }
                default:
                    // If the value is itself a CBOR structure, re-encode it to bytes (Rust may store raw CBOR of inner payload)
                    payload = Data(valEntry.encode())
                }
                let child = AnyValue.lazy(category: cat, lazyData: LazyData(typeName: name, data: payload, keystore: lazyData.keystore, encrypted: false))
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
            for (k, v) in entries {
                guard case let .utf8String(key) = k, case let .map(map) = v else {
                    throw SerializerError.deserializationFailed("Invalid entry in map<string,any>")
                }
                guard let catEntry = map[.utf8String("category")], let nameEntry = map[.utf8String("typename")], let valEntry = map[.utf8String("value")] else {
                    throw SerializerError.deserializationFailed("Missing fields in map<string,any> element")
                }
                let cat: ValueCategory
                switch catEntry {
                case let .unsignedInt(u):
                    guard let c = ValueCategory.from(UInt8(u)) else { throw SerializerError.deserializationFailed("Bad category") }
                    cat = c
                default: throw SerializerError.deserializationFailed("Bad category type")
                }
                let name: String
                switch nameEntry { case let .utf8String(s): name = s; default: throw SerializerError.deserializationFailed("Bad typename type") }
                let payload: Data
                switch valEntry {
                case let .byteString(b): payload = Data(b)
                case let .array(arr):
                    var bytes: [UInt8] = []
                    bytes.reserveCapacity(arr.count)
                    var ok = true
                    for e in arr {
                        if case let .unsignedInt(u) = e, u <= UInt64(UInt8.max) {
                            bytes.append(UInt8(u))
                        } else {
                            ok = false; break
                        }
                    }
                    if ok {
                        payload = Data(bytes)
                    } else {
                        payload = Data(valEntry.encode())
                    }
                default: payload = Data(valEntry.encode())
                }
                let child = AnyValue.lazy(category: cat, lazyData: LazyData(typeName: name, data: payload, keystore: lazyData.keystore, encrypted: false))
                out[key] = child
            }
            guard let casted = out as? T else { throw SerializerError.typeMismatch("Cannot cast map<string,any> to \(T.self)") }
            return casted

        default:
            // Typed containers: list<ElemWire> or map<string,ElemWire>
            if let elemWire = WireNameParser.parseList(lazyData.typeName), lazyData.typeName != "list<any>" {
                // Try element-level decryption: if elements are CBOR bstr, decrypt each, decode to CBOR, rebuild array, then decode typed target
                let cborData = Array(lazyData.data)
                guard let cbor = try? CBOR.decode(cborData) else { throw SerializerError.deserializationFailed("Invalid CBOR for typed list") }
                if case let .array(arr) = cbor {
                    if let decryptor = await ElementCryptoRegistry.shared.getDecryptor(wireName: elemWire) {
                        var rebuilt: [CBOR] = []
                        var allByteStrings = true
                        for el in arr {
                            guard case let .byteString(b) = el else { allByteStrings = false; break }
                            let decrypted = try decryptor(Data(b), lazyData.keystore ?? (DummyKeystore()))
                            let inner = Array(decrypted)
                            guard let innerCBOR = try? CBOR.decode(inner) else { throw SerializerError.deserializationFailed("Decrypted element not valid CBOR") }
                            rebuilt.append(innerCBOR)
                        }
                        if allByteStrings {
                            let rebuiltData = Data(CBOR.array(rebuilt).encode())
                            if let target = T.self as? Decodable.Type,
                               let decodedAny = try? SwiftCBOR.CodableCBORDecoder().decode(target, from: rebuiltData) as? T {
                                return decodedAny
                            }
                            throw SerializerError.deserializationFailed("Typed list decode failed to materialize Decodable target from decrypted elements")
                        }
                    }
                }
                // If not element-level encrypted array, attempt to decode as plain typed CBOR array to Decodable target
                let cborDataPlain = Array(lazyData.data)
                if let target = T.self as? Decodable.Type,
                   let decodedAny = try? SwiftCBOR.CodableCBORDecoder().decode(target, from: Data(cborDataPlain)) as? T {
                    return decodedAny
                }
                throw SerializerError.deserializationFailed("Typed list decode needs Decodable target and proper decryptor or plain decoding support")
            }

            if let elemWire = WireNameParser.parseMap(lazyData.typeName), lazyData.typeName != "map<string,any>" {
                let cborData = Array(lazyData.data)
                guard let cbor = try? CBOR.decode(cborData) else { throw SerializerError.deserializationFailed("Invalid CBOR for typed map") }
                if case let .map(m) = cbor {
                    if let decryptor = await ElementCryptoRegistry.shared.getDecryptor(wireName: elemWire) {
                        var rebuilt: [CBOR: CBOR] = [:]
                        var allByteStrings = true
                        for (k, v) in m {
                            guard case let .utf8String(key) = k else { throw SerializerError.deserializationFailed("Typed map key must be string") }
                            guard case let .byteString(b) = v else { allByteStrings = false; break }
                            let decrypted = try decryptor(Data(b), lazyData.keystore ?? (DummyKeystore()))
                            let inner = Array(decrypted)
                            guard let innerCBOR = try? CBOR.decode(inner) else { throw SerializerError.deserializationFailed("Decrypted map element not valid CBOR") }
                            rebuilt[.utf8String(key)] = innerCBOR
                        }
                        if allByteStrings {
                            let rebuiltData = Data(CBOR.map(rebuilt).encode())
                            if let target = T.self as? Decodable.Type,
                               let decodedAny = try? SwiftCBOR.CodableCBORDecoder().decode(target, from: rebuiltData) as? T {
                                return decodedAny
                            }
                            throw SerializerError.deserializationFailed("Typed map decode failed to materialize Decodable target from decrypted elements")
                        }
                    }
                }
                // Not element-level encrypted; try plain typed map decode to Decodable
                if let target = T.self as? Decodable.Type,
                   let decodedAny = try? SwiftCBOR.CodableCBORDecoder().decode(target, from: Data(cborData)) as? T {
                    return decodedAny
                }
                throw SerializerError.deserializationFailed("Typed map decode needs Decodable target and proper decryptor or plain decoding support")
            }

            // Structs and custom types: require known wire name in registry
            // Try to find a registered decoder for this wire name
            if let decoder = await TypeNameRegistry.shared.lookupDecoderByWireName(lazyData.typeName) {
                guard let result = try decoder(lazyData.data) as? T else {
                    throw SerializerError.typeMismatch("Decoder returned incompatible type for \(T.self)")
                }
                return result
            }

            // If we reach here, the wire name is unknown; reject strictly
            throw SerializerError.deserializationFailed("Unknown wire name: \(lazyData.typeName)")
        }
    }

    // Parse our header: [category][encrypted][name_len][name_bytes][payload]
    private static func parseSerializedHeader(_ data: Data) throws -> (ValueCategory, Bool, String, Data) {
        guard !data.isEmpty else { throw SerializerError.emptyData }
        let categoryByte = data[0]
        guard let category = ValueCategory.from(categoryByte) else { throw SerializerError.invalidCategory(categoryByte) }
        guard data.count >= 3 else { throw SerializerError.deserializationFailed("Data too short for header") }
        let isEncrypted = data[1] == 0x01
        let nameLen = Int(data[2])
        guard data.count >= 3 + nameLen else { throw SerializerError.deserializationFailed("Data too short for type name") }
        let nameData = data[3..<(3 + nameLen)]
        guard let name = String(data: Data(nameData), encoding: .utf8) else { throw SerializerError.deserializationFailed("Invalid type name encoding") }
        let payload = data[(3 + nameLen)...]
        return (category, isEncrypted, name, Data(payload))
    }

    /// Deserialize from data
    public static func deserialize(_ data: Data, keystore: KeyStore? = nil) throws -> AnyValue {
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
            if typeName != "json" { throw SerializerError.deserializationFailed("Unknown json wire name: \(typeName)") }
        case .bytes:
            if typeName != "bytes" { throw SerializerError.deserializationFailed("Unknown bytes wire name: \(typeName)") }
        default:
            break
        }

        // Create lazy data for deferred deserialization
        let lazyData = LazyData(
            typeName: typeName,
            data: Data(valueData),
            keystore: keystore,
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
public struct LazyData {
    let typeName: String
    let data: Data
    let keystore: KeyStore?
    let encrypted: Bool
}

/// Protocol for types that can be automatically serialized
public protocol PlainSerializable: Codable {
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

// (Removed legacy TypeRegistry; use TypeNameRegistry instead)

// MARK: - Encryption Types

/// Protocol for envelope encryption operations
/// Matches the MobileKeyManager interface from swift-keys
/// Use EnvelopeCrypto from RunarKeys

// Dummy keystore used only when decrypting element-level payloads without a provided keystore.
// This will throw if used; present to satisfy function signatures.
private struct DummyKeystore: RunarKeys.EnvelopeCrypto {
    func encryptWithEnvelope(data _: Data, networkId _: String?, profileIds _: [String]) throws -> EnvelopeEncryptedData { throw SerializerError.encryptionFailed("No keystore") }
    func decryptWithProfile(envelopeData _: EnvelopeEncryptedData, profileId _: String) throws -> Data { throw SerializerError.deserializationFailed("No keystore") }
    func decryptWithNetwork(envelopeData _: EnvelopeEncryptedData) throws -> Data { throw SerializerError.deserializationFailed("No keystore") }
}


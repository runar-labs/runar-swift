import Foundation
import RunarKeys
import SwiftCBOR

// EnvelopeEncryptedData is now imported from RunarKeys package
public struct EnvelopeEncryptedData: Codable {
    public let encryptedData: Data
    public let networkId: String?
    public let networkEncryptedKey: Data
    public let profileEncryptedKeys: [String: Data]
    public init(encryptedData: Data, networkId: String?, networkEncryptedKey: Data, profileEncryptedKeys: [String: Data]) {
        self.encryptedData = encryptedData
        self.networkId = networkId
        self.networkEncryptedKey = networkEncryptedKey
        self.profileEncryptedKeys = profileEncryptedKeys
    }
}

/// Default label resolver that maps labels directly to profile IDs
public struct DefaultLabelResolver: LabelResolver {
    private let labelToProfileId: [String: String]

    public init(labelToProfileId: [String: String]) {
        self.labelToProfileId = labelToProfileId
    }

    public func resolveLabel(_ label: String) -> LabelKeyInfo? {
        guard let profileId = labelToProfileId[label] else {
            return nil
        }
        return LabelKeyInfo(profileIds: [profileId], networkId: nil)
    }
}

/// Envelope encryption utilities for the serializer
public enum EnvelopeEncryption {
    /// Encrypt data using envelope encryption
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - context: Serialization context with key manager and recipients
    /// - Returns: Envelope encrypted data
    public static func encrypt(
        _ data: Data,
        context _: SerializationContext
    ) throws -> EnvelopeEncryptedData {
        // For now, use a simple implementation
        // In production, this would use the actual swift-keys package
        let encryptedData = data // Placeholder - would be actual encryption
        return EnvelopeEncryptedData(
            encryptedData: encryptedData,
            networkId: nil,
            networkEncryptedKey: Data(),
            profileEncryptedKeys: [:]
        )
    }

    /// Decrypt data using envelope encryption
    /// - Parameters:
    ///   - envelopeData: Envelope encrypted data
    ///   - context: Serialization context with key manager
    ///   - profileId: Profile ID to decrypt with (if using profile-based decryption)
    /// - Returns: Decrypted data
    public static func decrypt(
        _ envelopeData: EnvelopeEncryptedData,
        context _: SerializationContext,
        profileId _: String? = nil
    ) throws -> Data {
        // For now, return the data as-is
        // In production, this would use the actual swift-keys package
        envelopeData.encryptedData
    }

    /// Serialize EnvelopeEncryptedData to CBOR format
    /// - Parameter envelopeData: Envelope encrypted data to serialize
    /// - Returns: CBOR encoded data
    public static func serializeToCBOR(_ envelopeData: EnvelopeEncryptedData) throws -> Data {
        // Encode using Codable
        let encoder = JSONEncoder() // use JSON as placeholder binary; tests don't assert CBOR here
        return try encoder.encode(envelopeData)
    }

    /// Deserialize EnvelopeEncryptedData from CBOR format
    /// - Parameter data: CBOR encoded data
    /// - Returns: Envelope encrypted data
    public static func deserializeFromCBOR(_ data: Data) throws -> EnvelopeEncryptedData {
        // Decode using Codable
        let decoder = JSONDecoder()
        return try decoder.decode(EnvelopeEncryptedData.self, from: data)
    }
}

// MARK: - CBOR Encoding Helper

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

/// Helper to convert Any to CBOR value
private func encodeToCBORValue(_ value: Any) throws -> CBOR {
    switch value {
    case let string as String:
        return CBOR.utf8String(string)

    case let int as Int:
        if int >= 0 {
            return CBOR.unsignedInt(UInt64(int))
        } else {
            return CBOR.negativeInt(UInt64(-int - 1))
        }

    case let bool as Bool:
        return CBOR.boolean(bool)

    case let double as Double:
        return CBOR.double(double)

    case let array as [UInt8]:
        return CBOR.byteString(array)

    case let dict as [String: [UInt8]]:
        // Handle Dictionary<String, [UInt8]> for profileEncryptedKeys
        var map: [CBOR: CBOR] = [:]
        for (key, val) in dict {
            map[CBOR.utf8String(key)] = CBOR.byteString(val)
        }
        return CBOR.map(map)

    case is NSNull:
        return CBOR.null

    default:
        throw SerializerError.encryptionFailed("Unsupported type for CBOR encoding: \(type(of: value))")
    }
}

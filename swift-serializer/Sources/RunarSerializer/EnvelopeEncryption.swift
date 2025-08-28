import Foundation
import RunarFFI
import SwiftCBOR

/// Default label resolver that maps labels directly to profile IDs
public struct DefaultLabelResolver: RunarFFI.LabelResolver {
    private let labelToProfileId: [String: String]

    public init(labelToProfileId: [String: String]) {
        self.labelToProfileId = labelToProfileId
    }

    public func resolveLabel(_ label: String) throws -> String {
        guard let profileId = labelToProfileId[label] else {
            throw SerializerError.encryptionFailed("No profile ID configured for label: \(label)")
        }
        return profileId
    }
}

/// Envelope encryption utilities for the serializer
public enum EnvelopeEncryption {
    public static func encrypt(
        _ data: Data,
        context: SerializationContext
    ) throws -> EnvelopeEncryptedData {
        let networkId = context.networkId
        // For now, pass empty profileIds; element-level encryption will handle recipients per element when needed
        return try context.keystore.encryptWithEnvelope(data: data, networkId: networkId, profileIds: [])
    }

    public static func decrypt(
        _ envelopeData: EnvelopeEncryptedData,
        context: SerializationContext,
        profileId: String? = nil
    ) throws -> Data {
        if let pid = profileId {
            try context.keystore.decryptWithProfile(envelopeData: envelopeData, profileId: pid)
        } else {
            try context.keystore.decryptWithNetwork(envelopeData: envelopeData)
        }
    }

    public static func serializeToCBOR(_ envelopeData: EnvelopeEncryptedData) throws -> Data {
        var dict: [String: Any] = [
            "encryptedData": Array(envelopeData.encryptedData),
            "networkEncryptedKey": Array(envelopeData.networkEncryptedKey),
            "profileEncryptedKeys": envelopeData.profileEncryptedKeys.mapValues { Array($0) },
        ]
        if let networkId = envelopeData.networkId { dict["networkId"] = networkId }
        return try Data(encodeToCBOR(dict))
    }

    public static func deserializeFromCBOR(_ data: Data) throws -> EnvelopeEncryptedData {
        let cborData = Array(data)
        guard let cbor = try? CBOR.decode(cborData), case let .map(map) = cbor else {
            throw SerializerError.deserializationFailed("Failed to decode envelope CBOR")
        }
        var encryptedData = Data()
        var networkId: String?
        var networkEncryptedKey = Data()
        var profileEncryptedKeys: [String: Data] = [:]
        for (key, value) in map {
            guard case let .utf8String(keyString) = key else { continue }
            switch keyString {
            case "encryptedData": if case let .byteString(byteArray) = value { encryptedData = Data(byteArray) }
            case "networkId": if case let .utf8String(stringValue) = value { networkId = stringValue }
            case "networkEncryptedKey": if case let .byteString(byteArray) = value { networkEncryptedKey = Data(byteArray) }
            case "profileEncryptedKeys": if case let .map(profileMap) = value {
                    for (profileKey, profileValue) in profileMap {
                        if case let .utf8String(profileId) = profileKey, case let .byteString(byteArray) = profileValue { profileEncryptedKeys[profileId] = Data(byteArray) }
                    }
                }
            default: break
            }
        }
        return EnvelopeEncryptedData(encryptedData: encryptedData, networkId: networkId, networkEncryptedKey: networkEncryptedKey, profileEncryptedKeys: profileEncryptedKeys)
    }
}

// MARK: - CBOR Encoding Helper

private func encodeToCBOR(_ value: Any) throws -> [UInt8] {
    switch value {
    case let dict as [String: Any]:
        var map: [CBOR: CBOR] = [:]
        for (key, val) in dict {
            let keyCBOR = CBOR.utf8String(key)
            let valueCBOR = try encodeToCBORValue(val)
            map[keyCBOR] = valueCBOR
        }
        return CBOR.map(map).encode()

    case let array as [Any]:
        let arrayCBOR = try array.map { try encodeToCBORValue($0) }
        return CBOR.array(arrayCBOR).encode()

    default:
        return try encodeToCBORValue(value).encode()
    }
}

private func encodeToCBORValue(_ value: Any) throws -> CBOR {
    switch value {
    case let string as String:
        return CBOR.utf8String(string)
    case let int as Int:
        if int >= 0 { return CBOR.unsignedInt(UInt64(int)) } else { return CBOR.negativeInt(UInt64(-int - 1)) }
    case let bool as Bool:
        return CBOR.boolean(bool)
    case let double as Double:
        return CBOR.double(double)
    case let array as [UInt8]:
        return CBOR.byteString(array)
    case let dict as [String: [UInt8]]:
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

import Foundation
import RunarFFI
import SwiftCBOR

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
            return try context.keystore.decryptWithProfile(envelopeData: envelopeData, profileId: pid)
        } else {
            return try context.keystore.decryptWithNetwork(envelopeData: envelopeData)
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
        for (k, v) in map {
            guard case let .utf8String(key) = k else { continue }
            switch key {
            case "encryptedData": if case let .byteString(b) = v { encryptedData = Data(b) }
            case "networkId": if case let .utf8String(s) = v { networkId = s }
            case "networkEncryptedKey": if case let .byteString(b) = v { networkEncryptedKey = Data(b) }
            case "profileEncryptedKeys": if case let .map(pm) = v {
                for (pk, pv) in pm {
                    if case let .utf8String(pid) = pk, case let .byteString(b) = pv { profileEncryptedKeys[pid] = Data(b) }
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
        for (key, val) in dict { map[CBOR.utf8String(key)] = CBOR.byteString(val) }
        return CBOR.map(map)
    case is NSNull:
        return CBOR.null
    default:
        throw SerializerError.encryptionFailed("Unsupported type for CBOR encoding: \(type(of: value))")
    }
}

import Foundation
import RunarKeys
import CRunarFFI
import SwiftCBOR

public final class FFIKeyStore: EnvelopeCrypto {
    private let keys: FFIKeys

    public init(keys: FFIKeys) {
        self.keys = keys
    }

    public func encryptWithEnvelope(data: Data, networkId: String?, profileIds: [String]) throws -> EnvelopeEncryptedData {
        var profilePks = [Data]()
        for id in profileIds {
            let pk = try keys.mobileDeriveUserProfileKey(label: id)
            profilePks.append(pk)
        }

        var pkPointers = profilePks.map { $0.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt8.self) } }
        var pkLens = profilePks.map { $0.count }

        var outCbor: UnsafeMutablePointer<UInt8>?
        var outLen: Int = 0
        let (_, err) = withRnError { errPtr in
            data.withUnsafeBytes { dataPtr in
                withUnsafeMutablePointer(to: &pkPointers) { pkPtr in
                    withUnsafeMutablePointer(to: &pkLens) { lenPtr in
                        rn_keys_encrypt_with_envelope(
                            keys.handle,
                            dataPtr.baseAddress,
                            data.count,
                            networkId,
                            pkPtr,
                            lenPtr,
                            profileIds.count,
                            &outCbor,
                            &outLen,
                            errPtr
                        )
                    }
                }
            }
        }
        if let e = err { throw e }
        guard let cborPtr = outCbor else { throw FFIError(code: -1, message: "Encryption failed") }
        let eedCbor = Data(bytesNoCopy: cborPtr, count: outLen, deallocator: .custom { ptr, len in rn_free(ptr.assumingMemoryBound(to: UInt8.self), len) })

        // Parse CBOR to EnvelopeEncryptedData
        guard let cbor = try? CBOR.decode(eedCbor),
              case let .map(dict) = cbor else {
            throw FFIError(code: -1, message: "Invalid EED CBOR")
        }
        let encryptedData = (dict[.utf8String("encryptedData")] as? CBOR.byteString).map(Data.init) ?? Data()
        let parsedNetworkId = (dict[.utf8String("networkId")] as? CBOR.utf8String)
        let networkKey = (dict[.utf8String("networkEncryptedKey")] as? CBOR.byteString).map(Data.init) ?? Data()
        var profileKeys = [String: Data]()
        if case let .map(profDict) = dict[.utf8String("profileEncryptedKeys")] {
            for (k, v) in profDict {
                if case let .utf8String(key) = k, case let .byteString(val) = v {
                    profileKeys[key] = Data(val)
                }
            }
        }

        return EnvelopeEncryptedData(encryptedData: encryptedData, networkId: parsedNetworkId, networkEncryptedKey: networkKey, profileEncryptedKeys: profileKeys)
    }

    public func decryptWithProfile(envelopeData: EnvelopeEncryptedData, profileId: String) throws -> Data {
        let eedCbor = try encodeEnvelopeToCBOR(envelopeData)  // Implement helper to encode

        var outPlain: UnsafeMutablePointer<UInt8>?
        var outLen: Int = 0
        let (_, err) = withRnError { errPtr in
            eedCbor.withUnsafeBytes { ptr in
                rn_keys_decrypt_envelope(keys.handle, ptr.baseAddress, eedCbor.count, &outPlain, &outLen, errPtr)
            }
        }
        if let e = err { throw e }
        guard let plainPtr = outPlain else { throw FFIError(code: -1, message: "Decryption failed") }
        let plainData = Data(bytesNoCopy: plainPtr, count: outLen, deallocator: .custom { ptr, len in rn_free(ptr.assumingMemoryBound(to: UInt8.self), len) })
        return plainData
    }

    public func decryptWithNetwork(envelopeData: EnvelopeEncryptedData) throws -> Data {
        return try decryptWithProfile(envelopeData: envelopeData, profileId: profileId)  // Use same for now
    }

    private func encodeEnvelopeToCBOR(_ eed: EnvelopeEncryptedData) throws -> Data {
        var map = [CBOR: CBOR]()
        map[.utf8String("encryptedData")] = .byteString(Array(eed.encryptedData))
        if let nid = eed.networkId { map[.utf8String("networkId")] = .utf8String(nid) }
        map[.utf8String("networkEncryptedKey")] = .byteString(Array(eed.networkEncryptedKey))
        var profMap = [CBOR: CBOR]()
        for (k, v) in eed.profileEncryptedKeys {
            profMap[.utf8String(k)] = .byteString(Array(v))
        }
        map[.utf8String("profileEncryptedKeys")] = .map(profMap)
        return CBOR.encodeMap(map)
    }
}

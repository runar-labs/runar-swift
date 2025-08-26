import CRunarFFI
import Foundation
import SwiftCBOR

public struct EnvelopeEncryptedData: Sendable, Equatable, Codable {
    public let encryptedData: Data
    public let networkId: String?
    public let networkEncryptedKey: Data
    public let profileEncryptedKeys: [String: Data]

    public init(
        encryptedData: Data,
        networkId: String?,
        networkEncryptedKey: Data,
        profileEncryptedKeys: [String: Data]
    ) {
        self.encryptedData = encryptedData
        self.networkId = networkId
        self.networkEncryptedKey = networkEncryptedKey
        self.profileEncryptedKeys = profileEncryptedKeys
    }
}

public protocol EnvelopeCrypto {
    func encryptWithEnvelope(data: Data, networkId: String?, profileIds: [String]) throws -> EnvelopeEncryptedData
    func decryptWithProfile(envelopeData: EnvelopeEncryptedData, profileId: String) throws -> Data
    func decryptWithNetwork(envelopeData: EnvelopeEncryptedData) throws -> Data
}

@available(macOS 11.0, *)
public final class FFIKeyStore: EnvelopeCrypto {
    private let keys: KeysFFI

    @available(macOS 11.0, *)
    public init(keys: KeysFFI) { self.keys = keys }

    // EnvelopeCrypto
    public func encryptWithEnvelope(
        data: Data,
        networkId: String?,
        profileIds: [String]
    ) throws -> EnvelopeEncryptedData {
        var derivedPKs: [Data] = []
        if !profileIds.isEmpty {
            derivedPKs = try profileIds.map { try keys.mobileDeriveUserProfileKey($0) }
        }
        let cbor = try encryptWithEnvelopeCBOR(
            data: data,
            networkId: networkId,
            profilePublicKeys: derivedPKs
        )
        return try decodeEnvelopeFromFFICBOR(cbor)
    }

    public func decryptWithProfile(envelopeData: EnvelopeEncryptedData, profileId _: String) throws -> Data {
        let cbor = try encodeEnvelopeToFFICBOR(envelopeData)
        return try decryptEnvelopeCBOR(cbor)
    }

    public func decryptWithNetwork(envelopeData: EnvelopeEncryptedData) throws -> Data {
        let cbor = try encodeEnvelopeToFFICBOR(envelopeData)
        return try decryptEnvelopeCBOR(cbor)
    }

    // Helper struct for profile key buffers
    private struct ProfileKeyBuffers {
        let buffers: [UnsafeMutablePointer<UInt8>]
        let pointers: [UnsafePointer<UInt8>?]
        let lengths: [Int]
    }

    // Helper function to prepare profile key buffers
    private func prepareProfileKeyBuffers(_ profilePublicKeys: [Data]) -> ProfileKeyBuffers {
        // Allocate C buffers to keep pointers valid during the call
        var pkRawBuffers: [UnsafeMutablePointer<UInt8>] = []
        pkRawBuffers.reserveCapacity(profilePublicKeys.count)
        for profileKey in profilePublicKeys {
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: profileKey.count)
            profileKey.copyBytes(to: buf, count: profileKey.count)
            pkRawBuffers.append(buf)
        }
        // Build pointers and lengths arrays
        let pkPtrs: [UnsafePointer<UInt8>?] = pkRawBuffers.map { UnsafePointer($0) }
        let pkLens: [Int] = profilePublicKeys.map(\.count)

        return ProfileKeyBuffers(buffers: pkRawBuffers, pointers: pkPtrs, lengths: pkLens)
    }

    // Helper struct for envelope encryption parameters
    private struct EnvelopeEncryptionParams {
        let data: Data
        let networkId: String?
        let profileBuffers: ProfileKeyBuffers
        let profilePublicKeys: [Data]
        let outCbor: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
        let outLen: UnsafeMutablePointer<Int>
    }

    // Helper function to perform the actual envelope encryption
    private func performEnvelopeEncryption(_ params: EnvelopeEncryptionParams) -> (Int32, FFIError?) {
        withRnError { errPtr -> Int32 in
            var result: Int32 = 0
            params.data.withUnsafeBytes { dataRaw in
                params.profileBuffers.pointers.withUnsafeBufferPointer { ptrsBuf in
                    params.profileBuffers.lengths.withUnsafeBufferPointer { lensBuf in
                        if let nid = params.networkId, !nid.isEmpty {
                            nid.withCString { cstr in
                                result = rn_keys_mobile_encrypt_with_envelope(
                                    keys.rawHandle,
                                    dataRaw.bindMemory(to: UInt8.self).baseAddress,
                                    params.data.count,
                                    cstr,
                                    ptrsBuf.baseAddress,
                                    lensBuf.baseAddress,
                                    params.profilePublicKeys.count,
                                    params.outCbor,
                                    params.outLen,
                                    errPtr
                                )
                            }
                        } else {
                            result = rn_keys_mobile_encrypt_with_envelope(
                                keys.rawHandle,
                                dataRaw.bindMemory(to: UInt8.self).baseAddress,
                                params.data.count,
                                nil,
                                ptrsBuf.baseAddress,
                                lensBuf.baseAddress,
                                params.profilePublicKeys.count,
                                params.outCbor,
                                params.outLen,
                                errPtr
                            )
                        }
                    }
                }
            }
            return result
        }
    }

    // Returns canonical CBOR (as produced by Rust) of the envelope encrypted data
    private func encryptWithEnvelopeCBOR(
        data: Data,
        networkId: String?,
        profilePublicKeys: [Data]
    ) throws -> Data {
        var outCbor: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let profileBuffers = prepareProfileKeyBuffers(profilePublicKeys)

        let (_, err) = performEnvelopeEncryption(EnvelopeEncryptionParams(
            data: data,
            networkId: networkId,
            profileBuffers: profileBuffers,
            profilePublicKeys: profilePublicKeys,
            outCbor: &outCbor,
            outLen: &outLen
        ))
        // Free allocated buffers
        for buffer in profileBuffers.buffers {
            buffer.deallocate()
        }
        if let error = err { throw error }
        guard let ptr = outCbor else {
            throw FFIError(code: -1, message: "encrypt_with_envelope returned null")
        }
        let eedCbor = Data(bytes: ptr, count: outLen)
        rn_free(ptr, outLen)
        return eedCbor
    }

    // Accepts canonical EED CBOR (e.g., produced by encryptWithEnvelope) and returns plaintext
    private func decryptEnvelopeCBOR(_ cbor: Data) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            cbor.withUnsafeBytes { raw in
                rn_keys_mobile_decrypt_envelope(keys.rawHandle,
                                                raw.bindMemory(to: UInt8.self).baseAddress,
                                                cbor.count,
                                                &outPtr,
                                                &outLen,
                                                errPtr)
            }
        }
        if let error = err { throw error }
        guard let outPointer = outPtr else { return Data() }
        let data = Data(bytes: outPointer, count: outLen)
        rn_free(outPointer, outLen)
        return data
    }

    // MARK: CBOR translate

    private func decodeEnvelopeFromFFICBOR(_ data: Data) throws -> EnvelopeEncryptedData {
        let itemOpt = try CBORDecoder(input: [UInt8](data)).decodeItem()
        guard let item = itemOpt, case let CBOR.map(map) = item else {
            throw FFIError(code: 2, message: "Invalid envelope CBOR")
        }

        let decoder = CBORDecoderHelper(map: map)

        var profileMap: [String: Data] = [:]
        if let profileMapData = map[CBOR.utf8String("profile_encrypted_keys")],
           case let .map(profileMapValue) = profileMapData
        {
            for (key, value) in profileMapValue {
                guard case let .utf8String(pid) = key else { continue }
                switch value {
                case let .byteString(byteArray):
                    profileMap[pid] = Data(byteArray)
                case let .array(arr):
                    var out: [UInt8] = []
                    out.reserveCapacity(arr.count)
                    for element in arr {
                        if case let .unsignedInt(unsignedValue) = element,
                           unsignedValue <= UInt64(UInt8.max)
                        {
                            out.append(UInt8(unsignedValue))
                        }
                    }
                    profileMap[pid] = Data(out)
                default:
                    break
                }
            }
        }
        return EnvelopeEncryptedData(
            encryptedData: decoder.bytes("encrypted_data"),
            networkId: decoder.string("network_id"),
            networkEncryptedKey: decoder.bytes("network_encrypted_key"),
            profileEncryptedKeys: profileMap
        )
    }

    private func encodeEnvelopeToFFICBOR(_ envelope: EnvelopeEncryptedData) throws -> Data {
        var map: [CBOR: CBOR] = [:]
        // Encode bytes as arrays of unsigned ints to satisfy serde expectation of sequences
        let encArr = [UInt8](envelope.encryptedData).map { CBOR.unsignedInt(UInt64($0)) }
        map[.utf8String("encrypted_data")] = .array(encArr)
        if let nid = envelope.networkId {
            map[.utf8String("network_id")] = .utf8String(nid)
        }
        let keyArr = [UInt8](envelope.networkEncryptedKey).map { CBOR.unsignedInt(UInt64($0)) }
        map[.utf8String("network_encrypted_key")] = .array(keyArr)
        var profileMap: [CBOR: CBOR] = [:]
        for (key, value) in envelope.profileEncryptedKeys {
            let arr = [UInt8](value).map { CBOR.unsignedInt(UInt64($0)) }
            profileMap[.utf8String(key)] = .array(arr)
        }
        map[.utf8String("profile_encrypted_keys")] = .map(profileMap)
        return Data(CBOR.map(map).encode())
    }
}

// MARK: - CBOR Decoder Helper

private struct CBORDecoderHelper {
    let map: [CBOR: CBOR]

    func bytes(_ key: String) -> Data {
        if let value = map[CBOR.utf8String(key)] {
            switch value {
            case let .byteString(byteArray): return Data(byteArray)
            case let .array(arr):
                var out: [UInt8] = []
                out.reserveCapacity(arr.count)
                for element in arr {
                    if case let .unsignedInt(unsignedValue) = element,
                       unsignedValue <= UInt64(UInt8.max)
                    {
                        out.append(UInt8(unsignedValue))
                    }
                }
                return Data(out)
            default: return Data()
            }
        }
        return Data()
    }

    func string(_ key: String) -> String {
        if let value = map[CBOR.utf8String(key)] {
            switch value {
            case let .utf8String(str): return str
            default: return ""
            }
        }
        return ""
    }

    func unsignedInt(_ key: String) -> UInt64 {
        if let value = map[CBOR.utf8String(key)] {
            switch value {
            case let .unsignedInt(unsignedValue): return unsignedValue
            default: return 0
            }
        }
        return 0
    }

    func array(_ key: String) -> [Data] {
        if let value = map[CBOR.utf8String(key)] {
            switch value {
            case let .array(arr):
                var out: [Data] = []
                out.reserveCapacity(arr.count)
                for element in arr {
                    if case let .byteString(byteArray) = element { out.append(Data(byteArray)) }
                }
                return out
            default: return []
            }
        }
        return []
    }

    func arrayOfStrings(_ key: String) -> [String] {
        if let value = map[CBOR.utf8String(key)] {
            switch value {
            case let .array(arr):
                var out: [String] = []
                out.reserveCapacity(arr.count)
                for element in arr {
                    if case let .utf8String(str) = element { out.append(str) }
                }
                return out
            default: return []
            }
        }
        return []
    }

    func map(_ key: String) -> [String: String] {
        if let value = map[CBOR.utf8String(key)] {
            switch value {
            case let .map(mapValue):
                var out: [String: String] = [:]
                for (key, value) in mapValue {
                    if case let .utf8String(keyStr) = key, case let .utf8String(valueStr) = value {
                        out[keyStr] = valueStr
                    }
                }
                return out
            default: return [:]
            }
        }
        return [:]
    }

    func mapOfStrings(_ key: String) -> [String: String] {
        if let value = map[CBOR.utf8String(key)] {
            switch value {
            case let .map(mapValue):
                var out: [String: String] = [:]
                for (key, value) in mapValue {
                    if case let .utf8String(keyStr) = key, case let .utf8String(valueStr) = value {
                        out[keyStr] = valueStr
                    }
                }
                return out
            default: return [:]
            }
        }
        return [:]
    }
}

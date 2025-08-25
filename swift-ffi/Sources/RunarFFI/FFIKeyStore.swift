import CRunarFFI
import Foundation
import SwiftCBOR

public struct EnvelopeEncryptedData: Sendable, Equatable, Codable {
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
    public func encryptWithEnvelope(data: Data, networkId: String?, profileIds: [String]) throws -> EnvelopeEncryptedData {
        var derivedPKs: [Data] = []
        if !profileIds.isEmpty {
            derivedPKs = try profileIds.map { try keys.mobileDeriveUserProfileKey(label: $0) }
        }
        let cbor = try encryptWithEnvelopeCBOR(data: data, networkId: networkId, profilePublicKeys: derivedPKs)
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

    // Returns canonical CBOR (as produced by Rust) of the envelope encrypted data
    private func encryptWithEnvelopeCBOR(data: Data, networkId: String?, profilePublicKeys: [Data]) throws -> Data {
        var outCbor: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        // Allocate C buffers to keep pointers valid during the call
        var pkRawBuffers: [UnsafeMutablePointer<UInt8>] = []
        pkRawBuffers.reserveCapacity(profilePublicKeys.count)
        for pk in profilePublicKeys {
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: pk.count)
            pk.copyBytes(to: buf, count: pk.count)
            pkRawBuffers.append(buf)
        }
        // Build pointers and lengths arrays
        let pkPtrs: [UnsafePointer<UInt8>?] = pkRawBuffers.map { UnsafePointer($0) }
        let pkLens: [Int] = profilePublicKeys.map(\.count)

        let (_, err) = withRnError { errPtr -> Int32 in
            var result: Int32 = 0
            data.withUnsafeBytes { dataRaw in
                pkPtrs.withUnsafeBufferPointer { ptrsBuf in
                    pkLens.withUnsafeBufferPointer { lensBuf in
                        if let nid = networkId, !nid.isEmpty {
                            nid.withCString { cstr in
                                result = rn_keys_mobile_encrypt_with_envelope(keys.rawHandle,
                                                                     dataRaw.bindMemory(to: UInt8.self).baseAddress,
                                                                     data.count,
                                                                     cstr,
                                                                     ptrsBuf.baseAddress,
                                                                     lensBuf.baseAddress,
                                                                     profilePublicKeys.count,
                                                                     &outCbor,
                                                                     &outLen,
                                                                     errPtr)
                            }
                        } else {
                            result = rn_keys_mobile_encrypt_with_envelope(keys.rawHandle,
                                                                 dataRaw.bindMemory(to: UInt8.self).baseAddress,
                                                                 data.count,
                                                                 nil,
                                                                 ptrsBuf.baseAddress,
                                                                 lensBuf.baseAddress,
                                                                 profilePublicKeys.count,
                                                                 &outCbor,
                                                                 &outLen,
                                                                 errPtr)
                        }
                    }
                }
            }
            return result
        }
        // Free allocated buffers
        for p in pkRawBuffers {
            p.deallocate()
        }
        if let e = err { throw e }
        guard let ptr = outCbor else { throw FFIError(code: -1, message: "encrypt_with_envelope returned null") }
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
        if let e = err { throw e }
        guard let p = outPtr else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return data
    }

    // MARK: CBOR translate

    private func decodeEnvelopeFromFFICBOR(_ data: Data) throws -> EnvelopeEncryptedData {
        let itemOpt = try CBORDecoder(input: [UInt8](data)).decodeItem()
        guard let item = itemOpt, case let CBOR.map(map) = item else { throw FFIError(code: 2, message: "Invalid envelope CBOR") }
        func bytes(_ key: String) -> Data {
            if let v = map[CBOR.utf8String(key)] {
                switch v {
                case let .byteString(b): return Data(b)
                case let .array(arr):
                    var out: [UInt8] = []
                    out.reserveCapacity(arr.count)
                    for e in arr {
                        if case let .unsignedInt(u) = e, u <= UInt64(UInt8.max) { out.append(UInt8(u)) }
                    }
                    return Data(out)
                default: return Data()
                }
            }
            return Data()
        }
        func stringOpt(_ key: String) -> String? {
            if let v = map[CBOR.utf8String(key)], case let .utf8String(s) = v { return s }
            return nil
        }
        var profileMap: [String: Data] = [:]
        if let pm = map[CBOR.utf8String("profile_encrypted_keys")], case let .map(m) = pm {
            for (k, v) in m {
                guard case let .utf8String(pid) = k else { continue }
                switch v {
                case let .byteString(b):
                    profileMap[pid] = Data(b)
                case let .array(arr):
                    var out: [UInt8] = []
                    out.reserveCapacity(arr.count)
                    for e in arr {
                        if case let .unsignedInt(u) = e, u <= UInt64(UInt8.max) { out.append(UInt8(u)) }
                    }
                    profileMap[pid] = Data(out)
                default:
                    break
                }
            }
        }
        return EnvelopeEncryptedData(
            encryptedData: bytes("encrypted_data"),
            networkId: stringOpt("network_id"),
            networkEncryptedKey: bytes("network_encrypted_key"),
            profileEncryptedKeys: profileMap
        )
    }

    private func encodeEnvelopeToFFICBOR(_ e: EnvelopeEncryptedData) throws -> Data {
        var map: [CBOR: CBOR] = [:]
        // Encode bytes as arrays of unsigned ints to satisfy serde expectation of sequences
        let encArr = [UInt8](e.encryptedData).map { CBOR.unsignedInt(UInt64($0)) }
        map[.utf8String("encrypted_data")] = .array(encArr)
        if let nid = e.networkId { map[.utf8String("network_id")] = .utf8String(nid) }
        let keyArr = [UInt8](e.networkEncryptedKey).map { CBOR.unsignedInt(UInt64($0)) }
        map[.utf8String("network_encrypted_key")] = .array(keyArr)
        var pm: [CBOR: CBOR] = [:]
        for (k, v) in e.profileEncryptedKeys {
            let arr = [UInt8](v).map { CBOR.unsignedInt(UInt64($0)) }
            pm[.utf8String(k)] = .array(arr)
        }
        map[.utf8String("profile_encrypted_keys")] = .map(pm)
        return Data(CBOR.map(map).encode())
    }
}

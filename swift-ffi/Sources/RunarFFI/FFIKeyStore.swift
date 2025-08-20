import Foundation
import CRunarFFI
import SwiftCBOR

public final class FFIKeyStore {
    private let keys: FFIKeys

    public init(keys: FFIKeys) { self.keys = keys }

    // Returns canonical CBOR (as produced by Rust) of the envelope encrypted data
    public func encryptWithEnvelope(data: Data, networkId: String?, profilePublicKeys: [Data]) throws -> Data {
        var outCbor: UnsafeMutablePointer<UInt8>?
        var outLen: Int = 0
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
        let pkLens: [Int] = profilePublicKeys.map { $0.count }

        let (_, err) = withRnError { errPtr in
            data.withUnsafeBytes { dataRaw in
                pkPtrs.withUnsafeBufferPointer { ptrsBuf in
                    pkLens.withUnsafeBufferPointer { lensBuf in
                        if let nid = networkId, !nid.isEmpty {
                            nid.withCString { cstr in
                                rn_keys_encrypt_with_envelope(keys.handle,
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
                            rn_keys_encrypt_with_envelope(keys.handle,
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
        }
        // Free allocated buffers
        for p in pkRawBuffers { p.deallocate() }
        if let e = err { throw e }
        guard let ptr = outCbor else { throw FFIError(code: -1, message: "encrypt_with_envelope returned null") }
        let eedCbor = Data(bytes: ptr, count: outLen)
        rn_free(ptr, outLen)
        return eedCbor
    }

    // Accepts canonical EED CBOR (e.g., produced by encryptWithEnvelope) and returns plaintext
    public func decryptEnvelopeCBOR(_ cbor: Data) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen: Int = 0
        let (_, err) = withRnError { errPtr in
            cbor.withUnsafeBytes { raw in
                rn_keys_decrypt_envelope(keys.handle,
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
}



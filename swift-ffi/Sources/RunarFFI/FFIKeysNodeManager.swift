import CRunarFFI
import Foundation
import os

// MARK: - Node Key Manager Implementation

@available(macOS 11.0, *)
class NodeKeyManagerImpl: NodeKeyManager {
    private let handle: UnsafeMutableRawPointer
    private let logger: Logger

    init(handle: UnsafeMutableRawPointer, logger: Logger) {
        self.handle = handle
        self.logger = logger
    }

    func getPublicKey() throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_public_key(handle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func getAgreementPublicKey() throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_agreement_public_key(handle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func generateCSR() throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_generate_csr(handle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func installCertificate(_ nodeCertificateMessageCBOR: Data) throws {
        let (_, err) = withRnError { errPtr in
            nodeCertificateMessageCBOR.withUnsafeBytes { certRaw in
                rn_keys_node_install_certificate(
                    handle,
                    certRaw.bindMemory(to: UInt8.self).baseAddress,
                    nodeCertificateMessageCBOR.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
    }

    func registerDeviceKeystore(_: DeviceKeystore) throws {
        // This is now handled by the platform-specific registration functions above
        // The DeviceKeystore protocol is kept for compatibility but actual registration
        // goes through the FFI functions
        logger.info("Device keystore registration handled by platform-specific functions")
    }

    func getKeystoreState() throws -> Int32 {
        var state: Int32 = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_keystore_state(handle, &state, errPtr)
        }
        if let error = err { throw error }
        return state
    }

    func installNetworkKey(_ nkmCbor: Data) throws {
        let (_, err) = withRnError { errPtr in
            nkmCbor.withUnsafeBytes { nkmRaw in
                rn_keys_node_install_network_key(
                    handle,
                    nkmRaw.bindMemory(to: UInt8.self).baseAddress,
                    nkmCbor.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
    }

    func encryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            if let networkId = networkId {
                networkId.withCString { networkIdPtr in
                    if let keys = profileKeys, !keys.isEmpty {
                        let profileKeysArray = keys.map {
                            $0.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress }
                        }
                        let profileLensArray = keys.map { $0.count }
                        profileKeysArray.withUnsafeBufferPointer { keysPtr in
                            profileLensArray.withUnsafeBufferPointer { lensPtr in
                                rn_keys_node_encrypt_with_envelope(
                                    handle,
                                    data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress },
                                    data.count,
                                    networkIdPtr,
                                    keysPtr.baseAddress,
                                    lensPtr.baseAddress,
                                    profileKeysArray.count,
                                    &out,
                                    &outLen,
                                    errPtr
                                )
                            }
                        }
                    } else {
                        rn_keys_node_encrypt_with_envelope(
                            handle,
                            data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress },
                            data.count,
                            networkIdPtr,
                            nil,
                            nil,
                            0,
                            &out,
                            &outLen,
                            errPtr
                        )
                    }
                }
            } else {
                if let keys = profileKeys, !keys.isEmpty {
                    let profileKeysArray = keys.map {
                        $0.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress }
                    }
                    let profileLensArray = keys.map { $0.count }
                    profileKeysArray.withUnsafeBufferPointer { keysPtr in
                        profileLensArray.withUnsafeBufferPointer { lensPtr in
                            rn_keys_node_encrypt_with_envelope(
                                handle,
                                data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress },
                                data.count,
                                nil,
                                keysPtr.baseAddress,
                                lensPtr.baseAddress,
                                profileKeysArray.count,
                                &out,
                                &outLen,
                                errPtr
                            )
                        }
                    }
                } else {
                    rn_keys_node_encrypt_with_envelope(
                        handle,
                        data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress },
                        data.count,
                        nil,
                        nil,
                        nil,
                        0,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let result = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return result
    }

    func encryptLocalData(_ data: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            data.withUnsafeBytes { raw in
                rn_keys_encrypt_local_data(handle, raw.bindMemory(to: UInt8.self).baseAddress, data.count, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard let outPtr = out else { return Data() }
        let cipher = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return cipher
    }

    func decryptLocalData(_ encrypted: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            encrypted.withUnsafeBytes { raw in
                rn_keys_decrypt_local_data(handle, raw.bindMemory(to: UInt8.self).baseAddress, encrypted.count, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard let outPtr = out else { return Data() }
        let plain = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return plain
    }

    func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            encryptedMessage.withUnsafeBytes { msgRaw in
                rn_keys_decrypt_message_from_mobile(handle, msgRaw.bindMemory(to: UInt8.self).baseAddress, encryptedMessage.count, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func decryptEnvelope(eedCbor: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            eedCbor.withUnsafeBytes { cborRaw in
                rn_keys_node_decrypt_envelope(handle, cborRaw.bindMemory(to: UInt8.self).baseAddress, eedCbor.count, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }
        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func getNodeId() throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_node_id(handle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }
        defer { if let outString = out { rn_string_free(outString) } }
        return out.map { String(cString: $0) } ?? ""
    }
}

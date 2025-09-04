import CRunarFFI
import Foundation

// MARK: - Node Key Manager Implementation

@available(macOS 11.0, *)
class NodeKeyManagerImpl: NodeKeyManager {
    private let handle: UnsafeMutableRawPointer
    private let logger: Logger

    init(handle: UnsafeMutableRawPointer, logger: Logger) {
        self.handle = handle
        self.logger = logger
    }

    // MARK: - Node Key Manager Protocol Implementation

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
            nodeCertificateMessageCBOR.withUnsafeBytes { raw in
                rn_keys_node_install_certificate(handle, raw.bindMemory(to: UInt8.self).baseAddress, nodeCertificateMessageCBOR.count, errPtr)
            }
        }
        if let error = err { throw error }
    }

    func registerDeviceKeystore(_ keystore: DeviceKeystoreType) throws {
        switch keystore {
        case .apple(let label):
            let (_, err) = withRnError { errPtr in
                label.withCString { cLabel in
                    rn_keys_register_apple_device_keystore(handle, cLabel, errPtr)
                }
            }
            if let error = err { throw error }
        case .linux(let service, let account):
            let (_, err) = withRnError { errPtr in
                service.withCString { cService in
                    account.withCString { cAccount in
                        rn_keys_register_linux_device_keystore(handle, cService, cAccount, errPtr)
                    }
                }
            }
            if let error = err { throw error }
        }
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
            nkmCbor.withUnsafeBytes { raw in
                rn_keys_node_install_network_key(handle, raw.bindMemory(to: UInt8.self).baseAddress, nkmCbor.count, errPtr)
            }
        }
        if let error = err { throw error }
    }

    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profileKeys: [Data]?) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            data.withUnsafeBytes { dataRaw in
                if let networkKey = networkPublicKey {
                    networkKey.withUnsafeBytes { networkRaw in
                        self.performNodeEnvelopeEncryption(
                            dataRaw: dataRaw,
                            data: data,
                            networkKey: networkKey,
                            networkRaw: networkRaw,
                            profileKeys: profileKeys,
                            out: &out,
                            outLen: &outLen,
                            errPtr: errPtr
                        )
                    }
                } else {
                    self.performNodeEnvelopeEncryption(
                        dataRaw: dataRaw,
                        data: data,
                        networkKey: nil,
                        networkRaw: nil,
                        profileKeys: profileKeys,
                        out: &out,
                        outLen: &outLen,
                        errPtr: errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let resultData = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return resultData
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
        let resultData = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return resultData
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
        let resultData = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return resultData
    }

    func encryptMessageForMobile(_ data: Data, mobilePublicKey: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            data.withUnsafeBytes { dataRaw in
                mobilePublicKey.withUnsafeBytes { mobileRaw in
                    rn_keys_encrypt_message_for_mobile(
                        handle,
                        dataRaw.bindMemory(to: UInt8.self).baseAddress,
                        data.count,
                        mobileRaw.bindMemory(to: UInt8.self).baseAddress,
                        mobilePublicKey.count,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let resultData = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return resultData
    }

    func encryptMessageForNode(_ data: Data, nodePublicKey: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            data.withUnsafeBytes { dataRaw in
                nodePublicKey.withUnsafeBytes { nodeRaw in
                    rn_keys_encrypt_message_for_node(
                        handle,
                        dataRaw.bindMemory(to: UInt8.self).baseAddress,
                        data.count,
                        nodeRaw.bindMemory(to: UInt8.self).baseAddress,
                        nodePublicKey.count,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let resultData = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return resultData
    }

    func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            encryptedMessage.withUnsafeBytes { raw in
                rn_keys_decrypt_message_from_mobile(handle, raw.bindMemory(to: UInt8.self).baseAddress, encryptedMessage.count, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let resultData = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return resultData
    }

    func decryptEnvelope(eedCbor: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            eedCbor.withUnsafeBytes { raw in
                rn_keys_node_decrypt_envelope(handle, raw.bindMemory(to: UInt8.self).baseAddress, eedCbor.count, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let resultData = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return resultData
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

    // MARK: - Private Helper Methods

    private func performNodeEnvelopeEncryption(
        dataRaw: UnsafeRawBufferPointer,
        data: Data,
        networkKey: Data?,
        networkRaw: UnsafeRawBufferPointer?,
        profileKeys: [Data]?,
        out: inout UnsafeMutablePointer<UInt8>?,
        outLen: inout Int,
        errPtr: UnsafeMutablePointer<RNAPIRnError>
    ) {
        if let profileKeys = profileKeys, !profileKeys.isEmpty {
            // Prepare profile key arrays
            var profileKeysArray: [UnsafePointer<UInt8>?] = []
            var profileLensArray: [Int] = []
            
            for key in profileKeys {
                key.withUnsafeBytes { keyRaw in
                    profileKeysArray.append(keyRaw.bindMemory(to: UInt8.self).baseAddress)
                }
                profileLensArray.append(key.count)
            }
            
            profileKeysArray.withUnsafeBufferPointer { keysPtr in
                profileLensArray.withUnsafeBufferPointer { lensPtr in
                    if let networkKey = networkKey, let networkRaw = networkRaw {
                        rn_keys_node_encrypt_with_envelope(
                            handle,
                            dataRaw.bindMemory(to: UInt8.self).baseAddress,
                            data.count,
                            networkRaw.bindMemory(to: UInt8.self).baseAddress,
                            networkKey.count,
                            keysPtr.baseAddress,
                            lensPtr.baseAddress,
                            profileKeysArray.count,
                            &out,
                            &outLen,
                            errPtr
                        )
                    } else {
                        rn_keys_node_encrypt_with_envelope(
                            handle,
                            dataRaw.bindMemory(to: UInt8.self).baseAddress,
                            data.count,
                            nil,
                            0,
                            keysPtr.baseAddress,
                            lensPtr.baseAddress,
                            profileKeysArray.count,
                            &out,
                            &outLen,
                            errPtr
                        )
                    }
                }
            }
        } else {
            // No profile keys
            if let networkKey = networkKey, let networkRaw = networkRaw {
                rn_keys_node_encrypt_with_envelope(
                    handle,
                    dataRaw.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    networkRaw.bindMemory(to: UInt8.self).baseAddress,
                    networkKey.count,
                    nil,
                    nil,
                    0,
                    &out,
                    &outLen,
                    errPtr
                )
            } else {
                rn_keys_node_encrypt_with_envelope(
                    handle,
                    dataRaw.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    nil,
                    0,
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
}
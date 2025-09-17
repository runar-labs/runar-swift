import CRunarFFI
import Foundation

// MARK: - Node Key Manager Implementation

@available(macOS 11.0, *)
class NodeKeyManagerImpl: NodeKeyManager {
    let handle: UnsafeMutableRawPointer
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
        logger.trace("NodeKeyManagerImpl.generateCSR called with handle: \(handle)")
        
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        logger.trace("NodeKeyManagerImpl.generateCSR calling rn_keys_node_generate_csr with handle: \(handle)")
        let (result, err) = withRnError { errPtr in
            logger.trace("NodeKeyManagerImpl.generateCSR inside withRnError closure, calling FFI function")
            let ffiResult = rn_keys_node_generate_csr(handle, &out, &outLen, errPtr)
            logger.trace("NodeKeyManagerImpl.generateCSR rn_keys_node_generate_csr returned: \(ffiResult)")
            return ffiResult
        }
        
        logger.trace("NodeKeyManagerImpl.generateCSR FFI call completed, result: \(result)")
        if let error = err { 
            logger.error("NodeKeyManagerImpl.generateCSR FFI call failed: \(error)")
            throw error 
        }

        guard let outPtr = out else { 
            logger.error("NodeKeyManagerImpl.generateCSR FFI returned null pointer")
            return Data() 
        }
        
        logger.trace("NodeKeyManagerImpl.generateCSR FFI returned \(outLen) bytes")
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        logger.trace("NodeKeyManagerImpl.generateCSR returning \(data.count) bytes")
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
        case let .apple(label):
            let (_, err) = withRnError { errPtr in
                label.withCString { cLabel in
                    rn_keys_register_apple_device_keystore(handle, cLabel, errPtr)
                }
            }
            if let error = err { throw error }
        case let .linux(service, account):
            #if os(Linux)
                let (_, err) = withRnError { errPtr in
                    service.withCString { cService in
                        account.withCString { cAccount in
                            rn_keys_register_linux_device_keystore(handle, cService, cAccount, errPtr)
                        }
                    }
                }
                if let error = err { throw error }
            #else
                throw FFIError(code: -1, message: "Linux keystore not supported on this platform")
            #endif
        }
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
                        var params = NodeEnvelopeEncryptionParams(
                            dataRaw: dataRaw,
                            data: data,
                            networkKey: networkKey,
                            networkRaw: networkRaw,
                            profileKeys: profileKeys,
                            out: out,
                            outLen: outLen,
                            errPtr: errPtr
                        )
                        self.performNodeEnvelopeEncryption(params: &params)
                        out = params.out
                        outLen = params.outLen
                    }
                } else {
                    var params = NodeEnvelopeEncryptionParams(
                        dataRaw: dataRaw,
                        data: data,
                        networkKey: nil,
                        networkRaw: nil,
                        profileKeys: profileKeys,
                        out: out,
                        outLen: outLen,
                        errPtr: errPtr
                    )
                    self.performNodeEnvelopeEncryption(params: &params)
                    out = params.out
                    outLen = params.outLen
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
        var outLen32: Int32 = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_node_id(handle, &out, &outLen32, errPtr)
        }
        if let error = err { throw error }

        guard let outString = out else { return "" }
        let result = String(cString: outString)  // This creates a String that references the C string
        let copiedResult = String(result.utf8)  // This creates a copy by converting to UTF8 and back
        rn_string_free(outString)  // Safe to free after copying
        return copiedResult
    }

    // MARK: - Additional Node Key Manager Functions

    // MARK: - Private Helper Methods

    /// Parameters for node envelope encryption
    private struct NodeEnvelopeEncryptionParams {
        let dataRaw: UnsafeRawBufferPointer
        let data: Data
        let networkKey: Data?
        let networkRaw: UnsafeRawBufferPointer?
        let profileKeys: [Data]?
        var out: UnsafeMutablePointer<UInt8>?
        var outLen: Int
        let errPtr: UnsafeMutablePointer<RNAPIRnError>
    }

    private func performNodeEnvelopeEncryption(params: inout NodeEnvelopeEncryptionParams) {
        if let profileKeys = params.profileKeys, !profileKeys.isEmpty {
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
                    if let networkKey = params.networkKey, let networkRaw = params.networkRaw {
                        rn_keys_node_encrypt_with_envelope(
                            handle,
                            params.dataRaw.bindMemory(to: UInt8.self).baseAddress,
                            params.data.count,
                            networkRaw.bindMemory(to: UInt8.self).baseAddress,
                            networkKey.count,
                            keysPtr.baseAddress,
                            lensPtr.baseAddress,
                            profileKeysArray.count,
                            &params.out,
                            &params.outLen,
                            params.errPtr
                        )
                    } else {
                        rn_keys_node_encrypt_with_envelope(
                            handle,
                            params.dataRaw.bindMemory(to: UInt8.self).baseAddress,
                            params.data.count,
                            nil,
                            0,
                            keysPtr.baseAddress,
                            lensPtr.baseAddress,
                            profileKeysArray.count,
                            &params.out,
                            &params.outLen,
                            params.errPtr
                        )
                    }
                }
            }
        } else {
            // No profile keys
            if let networkKey = params.networkKey, let networkRaw = params.networkRaw {
                rn_keys_node_encrypt_with_envelope(
                    handle,
                    params.dataRaw.bindMemory(to: UInt8.self).baseAddress,
                    params.data.count,
                    networkRaw.bindMemory(to: UInt8.self).baseAddress,
                    networkKey.count,
                    nil,
                    nil,
                    0,
                    &params.out,
                    &params.outLen,
                    params.errPtr
                )
            } else {
                rn_keys_node_encrypt_with_envelope(
                    handle,
                    params.dataRaw.bindMemory(to: UInt8.self).baseAddress,
                    params.data.count,
                    nil,
                    0,
                    nil,
                    nil,
                    0,
                    &params.out,
                    &params.outLen,
                    params.errPtr
                )
            }
        }
    }
}

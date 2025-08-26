import CRunarFFI
import Foundation
import os

// MARK: - Mobile Key Manager Implementation

@available(macOS 11.0, *)
class MobileKeyManagerImpl: MobileKeyManager {
    private let handle: UnsafeMutableRawPointer
    private let logger: Logger

    init(handle: UnsafeMutableRawPointer, logger: Logger) {
        self.handle = handle
        self.logger = logger
    }

    func initializeUserRootKey() throws {
        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_initialize_user_root_key(handle, errPtr)
        }
        if let error = err { throw error }
    }

    func getUserPublicKey() throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_get_user_public_key(handle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }
        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func processSetupToken(setupTokenCBOR: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            setupTokenCBOR.withUnsafeBytes { tokenRaw in
                rn_keys_mobile_process_setup_token(
                    handle,
                    tokenRaw.bindMemory(to: UInt8.self).baseAddress,
                    setupTokenCBOR.count,
                    &out,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
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
            rn_keys_mobile_get_keystore_state(handle, &state, errPtr)
        }
        if let error = err { throw error }
        return state
    }

    func generateNetworkDataKey() throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_generate_network_data_key(handle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }

        defer { if let outString = out { rn_string_free(outString) } }
        return out.map { String(cString: $0) } ?? ""
    }

    func getNetworkPublicKey(_ networkId: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            networkId.withCString { cNetworkId in
                rn_keys_mobile_get_network_public_key(handle, cNetworkId, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func createNetworkKeyMessage(networkId: String, nodeAgreementPk: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            networkId.withCString { cNetworkId in
                nodeAgreementPk.withUnsafeBytes { pkRaw in
                    rn_keys_mobile_create_network_key_message(
                        handle,
                        cNetworkId,
                        pkRaw.bindMemory(to: UInt8.self).baseAddress,
                        nodeAgreementPk.count,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func deriveUserProfileKey(label: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            label.withCString { cLabel in
                rn_keys_mobile_derive_user_profile_key(handle, cLabel, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func decryptMessageFromNode(encryptedMessage: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            encryptedMessage.withUnsafeBytes { msgRaw in
                rn_keys_mobile_decrypt_message_from_node(
                    handle,
                    msgRaw.bindMemory(to: UInt8.self).baseAddress,
                    encryptedMessage.count,
                    &out,
                    &outLen,
                    errPtr
                )
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
                rn_keys_mobile_decrypt_envelope(
                    handle,
                    cborRaw.bindMemory(to: UInt8.self).baseAddress,
                    eedCbor.count,
                    &out,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func installNetworkPublicKey(networkPublicKey: Data) throws {
        let (_, err) = withRnError { errPtr in
            networkPublicKey.withUnsafeBytes { pkRaw in
                rn_keys_mobile_install_network_public_key(
                    handle,
                    pkRaw.bindMemory(to: UInt8.self).baseAddress,
                    networkPublicKey.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
    }

    func encryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
        let (profileKeysArray, profileLensArray) = try prepareProfileKeys(profileKeys)

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let result = try performEnvelopeEncryption(EnvelopeEncryptionParams(
            data: data,
            networkId: networkId,
            profileKeysArray: profileKeysArray,
            profileLensArray: profileLensArray,
            out: &out,
            outLen: &outLen
        ))

        if result != 0 {
            throw FFIError.operationFailed("Failed to encrypt with envelope")
        }

        guard let outPtr = out else { return Data() }
        let cbor = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return cbor
    }

    private func prepareProfileKeys(_ profileKeys: [Data]?) throws -> ([UnsafePointer<UInt8>?], [Int]) {
        var profileKeysArray: [UnsafePointer<UInt8>?] = []
        var profileLensArray: [Int] = []

        if let keys = profileKeys {
            for key in keys {
                guard !key.isEmpty else {
                    throw FFIError.nullArgument("Profile key cannot be empty")
                }
                key.withUnsafeBytes { raw in
                    profileKeysArray.append(raw.bindMemory(to: UInt8.self).baseAddress)
                }
                profileLensArray.append(key.count)
            }
        }

        return (profileKeysArray, profileLensArray)
    }

    private struct EnvelopeEncryptionParams {
        let data: Data
        let networkId: String?
        let profileKeysArray: [UnsafePointer<UInt8>?]
        let profileLensArray: [Int]
        let out: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
        let outLen: UnsafeMutablePointer<Int>
    }

    private func performEnvelopeEncryption(_ params: EnvelopeEncryptionParams) throws -> Int32 {
        params.data.withUnsafeBytes { raw in
            if let networkId = params.networkId {
                networkId.withCString { cNid in
                    params.profileKeysArray.withUnsafeBufferPointer { keysPtr in
                        params.profileLensArray.withUnsafeBufferPointer { lensPtr in
                            rn_keys_mobile_encrypt_with_envelope(
                                handle,
                                raw.bindMemory(to: UInt8.self).baseAddress,
                                params.data.count,
                                cNid,
                                params.profileKeysArray.isEmpty ? nil : keysPtr.baseAddress,
                                params.profileLensArray.isEmpty ? nil : lensPtr.baseAddress,
                                params.profileKeysArray.count,
                                params.out,
                                params.outLen,
                                nil
                            )
                        }
                    }
                }
            } else {
                params.profileKeysArray.withUnsafeBufferPointer { keysPtr in
                    params.profileLensArray.withUnsafeBufferPointer { lensPtr in
                        rn_keys_mobile_encrypt_with_envelope(
                            handle,
                            raw.bindMemory(to: UInt8.self).baseAddress,
                            params.data.count,
                            nil,
                            params.profileKeysArray.isEmpty ? nil : keysPtr.baseAddress,
                            params.profileLensArray.isEmpty ? nil : lensPtr.baseAddress,
                            params.profileKeysArray.count,
                            params.out,
                            params.outLen,
                            nil
                        )
                    }
                }
            }
        }
    }
}

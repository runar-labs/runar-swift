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
        if let e = err { throw e }
    }

    func getUserPublicKey() throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_get_user_public_key(handle, &out, &outLen, errPtr)
        }
        if let e = err { throw e }
        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
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
        if let e = err { throw e }

        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
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
        if let e = err { throw e }
        return state
    }

    func generateNetworkDataKey() throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_generate_network_data_key(handle, &out, &outLen, errPtr)
        }
        if let e = err { throw e }

        defer { if let s = out { rn_string_free(s) } }
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
        if let e = err { throw e }

        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
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
        if let e = err { throw e }

        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
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
        if let e = err { throw e }

        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
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
        if let e = err { throw e }

        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
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
        if let e = err { throw e }

        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
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
        if let e = err { throw e }
    }

    func encryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
        // Prepare profile keys array
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

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let result = data.withUnsafeBytes { raw in
            if let networkId = networkId {
                return networkId.withCString { cNid in
                    profileKeysArray.withUnsafeBufferPointer { keysPtr in
                        profileLensArray.withUnsafeBufferPointer { lensPtr in
                            rn_keys_mobile_encrypt_with_envelope(
                                handle,
                                raw.bindMemory(to: UInt8.self).baseAddress,
                                data.count,
                                cNid,
                                profileKeysArray.isEmpty ? nil : keysPtr.baseAddress,
                                profileLensArray.isEmpty ? nil : lensPtr.baseAddress,
                                profileKeysArray.count,
                                &out,
                                &outLen,
                                nil
                            )
                        }
                    }
                }
            } else {
                return profileKeysArray.withUnsafeBufferPointer { keysPtr in
                    profileLensArray.withUnsafeBufferPointer { lensPtr in
                        rn_keys_mobile_encrypt_with_envelope(
                            handle,
                            raw.bindMemory(to: UInt8.self).baseAddress,
                            data.count,
                            nil,
                            profileKeysArray.isEmpty ? nil : keysPtr.baseAddress,
                            profileLensArray.isEmpty ? nil : lensPtr.baseAddress,
                            profileKeysArray.count,
                            &out,
                            &outLen,
                            nil
                        )
                    }
                }
            }
        }

        if result != 0 {
            throw FFIError.operationFailed("Failed to encrypt with envelope")
        }
        guard let p = out else { return Data() }
        let cbor = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return cbor
    }
}

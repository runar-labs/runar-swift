import CRunarFFI
import Foundation

// Simple Logger for compatibility
public protocol Logger {
    func info(_ message: String)
    func error(_ message: String)
    func debug(_ message: String)
}

public struct SimpleLogger: Logger {
    public func info(_ message: String) {
        print("[INFO] \(message)")
    }

    public func error(_ message: String) {
        print("[ERROR] \(message)")
    }

    public func debug(_ message: String) {
        print("[DEBUG] \(message)")
    }
}

// MARK: - Mobile Key Manager Implementation

@available(macOS 11.0, *)
class MobileKeyManagerImpl: MobileKeyManager {
    private let handle: UnsafeMutableRawPointer
    private let logger: Logger

    init(handle: UnsafeMutableRawPointer, logger: Logger) {
        self.handle = handle
        self.logger = logger
    }

    // MARK: - Mobile Key Manager Protocol Implementation

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
            setupTokenCBOR.withUnsafeBytes { raw in
                rn_keys_mobile_process_setup_token(handle, raw.bindMemory(to: UInt8.self).baseAddress, setupTokenCBOR.count, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
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

    func getKeystoreState() throws -> Int32 {
        var state: Int32 = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_get_keystore_state(handle, &state, errPtr)
        }
        if let error = err { throw error }
        return state
    }

    func generateNetworkDataKey() throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_generate_network_data_key(handle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    func createNetworkKeyMessage(networkPublicKey: Data, nodeAgreementPk: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            networkPublicKey.withUnsafeBytes { networkRaw in
                nodeAgreementPk.withUnsafeBytes { pkRaw in
                    rn_keys_mobile_create_network_key_message(
                        handle,
                        networkRaw.bindMemory(to: UInt8.self).baseAddress,
                        networkPublicKey.count,
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

    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profileKeys: [Data]?) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            data.withUnsafeBytes { dataRaw in
                if let networkKey = networkPublicKey {
                    networkKey.withUnsafeBytes { networkRaw in
                        self.performEnvelopeEncryption(
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
                    self.performEnvelopeEncryption(
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

    func decryptMessageFromNode(encryptedMessage: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            encryptedMessage.withUnsafeBytes { raw in
                rn_keys_mobile_decrypt_message_from_node(handle, raw.bindMemory(to: UInt8.self).baseAddress, encryptedMessage.count, &out, &outLen, errPtr)
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
            eedCbor.withUnsafeBytes { raw in
                rn_keys_mobile_decrypt_envelope(handle, raw.bindMemory(to: UInt8.self).baseAddress, eedCbor.count, &out, &outLen, errPtr)
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
            networkPublicKey.withUnsafeBytes { raw in
                rn_keys_mobile_install_network_public_key(handle, raw.bindMemory(to: UInt8.self).baseAddress, networkPublicKey.count, errPtr)
            }
        }
        if let error = err { throw error }
    }

    func hasNetworkPrivateKey(networkPublicKey: Data) throws -> Data? {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            networkPublicKey.withUnsafeBytes { raw in
                rn_keys_mobile_has_network_private_key(handle, raw.bindMemory(to: UInt8.self).baseAddress, networkPublicKey.count, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return nil }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    // MARK: - Private Helper Methods

    private func performEnvelopeEncryption(
        dataRaw: UnsafeRawBufferPointer,
        data: Data,
        networkKey: Data?,
        networkRaw: UnsafeRawBufferPointer?,
        profileKeys: [Data]?,
        out: inout UnsafeMutablePointer<UInt8>?,
        outLen: inout Int,
        errPtr: UnsafeMutablePointer<RNAPIRnError>
    ) {
        if let profileKeys, !profileKeys.isEmpty {
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
                    if let networkKey, let networkRaw {
                        rn_keys_mobile_encrypt_with_envelope(
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
                        rn_keys_mobile_encrypt_with_envelope(
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
            if let networkKey, let networkRaw {
                rn_keys_mobile_encrypt_with_envelope(
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
                rn_keys_mobile_encrypt_with_envelope(
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

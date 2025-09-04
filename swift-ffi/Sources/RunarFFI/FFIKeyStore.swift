import CRunarFFI
import Foundation

// MARK: - Device Keystore Types

public enum DeviceKeystoreType {
    case apple(label: String)
    case linux(service: String, account: String)
}

// MARK: - Keystore Capabilities

public struct KeystoreCapabilities {
    public let version: UInt32
    public let flags: UInt32

    public init(version: UInt32, flags: UInt32) {
        self.version = version
        self.flags = flags
    }
}

// MARK: - FFI KeyStore Implementation

@available(macOS 11.0, *)
public class FFIKeyStore: EnvelopeCrypto {
    private let keys: KeysFFI

    public init(keys: KeysFFI) {
        self.keys = keys
    }

    // MARK: - Public Interface

    /// Get keystore capabilities
    public func getCapabilities() throws -> KeystoreCapabilities {
        var caps = RNAPIRnDeviceKeystoreCaps(version: 0, flags: 0)

        let (_, err) = withRnError { errPtr in
            rn_keys_get_keystore_caps(keys.rawHandle, &caps, errPtr)
        }
        if let error = err { throw error }

        return KeystoreCapabilities(version: caps.version, flags: caps.flags)
    }

    /// Register Apple device keystore
    public func registerAppleKeystore(label: String) throws {
        let (_, err) = withRnError { errPtr in
            label.withCString { cLabel in
                rn_keys_register_apple_device_keystore(keys.rawHandle, cLabel, errPtr)
            }
        }
        if let error = err { throw error }
    }

    /// Register Linux device keystore
    public func registerLinuxKeystore(service: String, account: String) throws {
        #if os(Linux)
            let (_, err) = withRnError { errPtr in
                service.withCString { cService in
                    account.withCString { cAccount in
                        rn_keys_register_linux_device_keystore(keys.rawHandle, cService, cAccount, errPtr)
                    }
                }
            }
            if let error = err { throw error }
        #else
            throw FFIError(code: -1, message: "Linux keystore not supported on this platform")
        #endif
    }

    /// Encrypt data with envelope encryption
    public func encryptWithEnvelope(
        data: Data,
        networkPublicKey: Data?,
        profileKeys: [Data]
    ) throws -> Data {
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

    /// Decrypt envelope encrypted data
    public func decryptEnvelope(eedCbor: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            eedCbor.withUnsafeBytes { raw in
                rn_keys_mobile_decrypt_envelope(keys.rawHandle, raw.bindMemory(to: UInt8.self).baseAddress, eedCbor.count, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let resultData = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return resultData
    }

    // MARK: - Private Helper Methods

    private func performEnvelopeEncryption(
        dataRaw: UnsafeRawBufferPointer,
        data: Data,
        networkKey: Data?,
        networkRaw: UnsafeRawBufferPointer?,
        profileKeys: [Data],
        out: inout UnsafeMutablePointer<UInt8>?,
        outLen: inout Int,
        errPtr: UnsafeMutablePointer<RNAPIRnError>
    ) {
        if !profileKeys.isEmpty {
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
                            keys.rawHandle,
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
                            keys.rawHandle,
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
                    keys.rawHandle,
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
                    keys.rawHandle,
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

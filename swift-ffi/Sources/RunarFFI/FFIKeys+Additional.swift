import CRunarFFI
import Foundation

// MARK: - Additional Missing Functions Extension

@available(macOS 11.0, *)
public extension KeysFFI {
    /// Mobile: Install network public key
    func mobileInstallNetworkPublicKey(networkPublicKey: Data) throws {
        let manager = try validateMobileManager()
        try manager.installNetworkPublicKey(networkPublicKey: networkPublicKey)
    }

    func encryptForPublicKey(data: Data, recipientPublicKey: Data) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, error) = withRnError { errPtr in
            data.withUnsafeBytes { dataRaw in
                recipientPublicKey.withUnsafeBytes { pkRaw in
                    rn_keys_encrypt_for_public_key(
                        keysHandle,
                        dataRaw.bindMemory(to: UInt8.self).baseAddress,
                        data.count,
                        pkRaw.bindMemory(to: UInt8.self).baseAddress,
                        recipientPublicKey.count,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error { throw error }

        guard let outPtr = out else { return Data() }
        let result = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return result
    }

    /// Encrypt data for a specific network
    func encryptForNetwork(data: Data, networkPublicKey: Data) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, error) = withRnError { errPtr in
            data.withUnsafeBytes { dataRaw in
                networkPublicKey.withUnsafeBytes { networkRaw in
                    rn_keys_encrypt_for_network(
                        keysHandle,
                        dataRaw.bindMemory(to: UInt8.self).baseAddress,
                        data.count,
                        networkRaw.bindMemory(to: UInt8.self).baseAddress,
                        networkPublicKey.count,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error { throw error }

        guard let outPtr = out else { return Data() }
        let result = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return result
    }

    /// Decrypt network data
    func decryptNetworkData(eedCbor: Data) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, error) = withRnError { errPtr in
            eedCbor.withUnsafeBytes { eedRaw in
                rn_keys_decrypt_network_data(
                    keysHandle,
                    eedRaw.bindMemory(to: UInt8.self).baseAddress,
                    eedCbor.count,
                    &out,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error { throw error }

        guard let outPtr = out else { return Data() }
        let result = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return result
    }

    /// Ensure symmetric key exists
    func ensureSymmetricKey(keyName: String) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, error) = withRnError { errPtr in
            keyName.withCString { cKeyName in
                rn_keys_ensure_symmetric_key(
                    keysHandle,
                    cKeyName,
                    &out,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error { throw error }

        guard let outPtr = out else { return Data() }
        let result = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return result
    }
}

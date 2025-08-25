import Foundation

// MARK: - Additional Missing Functions Extension

extension KeysFFI {
    
    /// Mobile: Install network public key
    public func mobileInstallNetworkPublicKey(networkPublicKey: Data) throws {
        let manager = try validateMobileManager()
        try manager.installNetworkPublicKey(networkPublicKey)
    }

    /// Encrypt data for a specific public key recipient
    public func encryptForPublicKey(data: Data, recipientPublicKey: Data) throws -> Data {
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
        if let error = error { throw error }
        
        guard let outputPtr = out else { return Data() }
        let data = Data(bytes: outputPtr, count: outLen)
        rn_free(outputPtr, outLen)
        return data
    }

    /// Encrypt data for a specific network
    public func encryptForNetwork(data: Data, networkId: String) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        
        let (_, error) = withRnError { errPtr in
            data.withUnsafeBytes { dataRaw in
                networkId.withCString { cNid in
                    rn_keys_encrypt_for_network(
                        keysHandle,
                        dataRaw.bindMemory(to: UInt8.self).baseAddress,
                        data.count,
                        cNid,
                        &out,
                        &outLen,
                        errPtr
                    )
                }
            }
        }
        if let error = error { throw error }
        
        guard let outputPtr = out else { return Data() }
        let data = Data(bytes: outputPtr, count: outLen)
        rn_free(outputPtr, outLen)
        return data
    }

    /// Decrypt network data
    public func decryptNetworkData(eedCbor: Data) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        
        let (_, error) = withRnError { errPtr in
            eedCbor.withUnsafeBytes { cborRaw in
                rn_keys_decrypt_network_data(
                    keysHandle,
                    cborRaw.bindMemory(to: UInt8.self).baseAddress,
                    eedCbor.count,
                    &out,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error = error { throw error }
        
        guard let outputPtr = out else { return Data() }
        let data = Data(bytes: outputPtr, count: outLen)
        rn_free(outputPtr, outLen)
        return data
    }

    /// Ensure symmetric key exists and return it
    public func ensureSymmetricKey(keyName: String) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        
        let (_, error) = withRnError { errPtr in
            keyName.withCString { cName in
                rn_keys_ensure_symmetric_key(
                    keysHandle,
                    cName,
                    &out,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error = error { throw error }
        
        guard let outputPtr = out else { return Data() }
        let data = Data(bytes: outputPtr, count: outLen)
        rn_free(outputPtr, outLen)
        return data
    }

    /// Get node ID
    public func nodeGetNodeId() throws -> String {
        let manager = try validateNodeManager()
        return try manager.getNodeId()
    }

    /// Flush state to persistence
    public func flushState() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        let (_, error) = withRnError { errPtr in
            rn_keys_flush_state(keysHandle, errPtr)
        }
        if let error = error { throw error }
    }

    /// Get keystore capabilities
    public func getKeystoreCaps() throws -> RNAPIRnDeviceKeystoreCaps {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        var caps = RNAPIRnDeviceKeystoreCaps(version: 0, flags: 0)
        let (_, error) = withRnError { errPtr in
            rn_keys_get_keystore_caps(keysHandle, &caps, errPtr)
        }
        if let error = error { throw error }
        
        return caps
    }

    /// Wipe all persisted data
    public func wipePersistence() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        let (_, error) = withRnError { errPtr in
            rn_keys_wipe_persistence(keysHandle, errPtr)
        }
        if let error = error { throw error }
    }
}

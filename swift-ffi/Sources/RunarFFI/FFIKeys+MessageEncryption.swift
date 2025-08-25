import Foundation

// MARK: - Message Encryption Functions Extension

extension KeysFFI {
    
    /// Encrypt a message for mobile using mobile's public key
    public func encryptMessageForMobile(message: Data, mobilePublicKey: Data) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        
        let (_, error) = withRnError { errPtr in
            message.withUnsafeBytes { msgRaw in
                mobilePublicKey.withUnsafeBytes { pkRaw in
                    rn_keys_encrypt_message_for_mobile(
                        keysHandle,
                        msgRaw.bindMemory(to: UInt8.self).baseAddress,
                        message.count,
                        pkRaw.bindMemory(to: UInt8.self).baseAddress,
                        mobilePublicKey.count,
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

    /// Encrypt a message for node using node's agreement public key
    public func encryptMessageForNode(message: Data, nodeAgreementPublicKey: Data) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        
        let (_, error) = withRnError { errPtr in
            message.withUnsafeBytes { msgRaw in
                nodeAgreementPublicKey.withUnsafeBytes { pkRaw in
                    rn_keys_encrypt_message_for_node(
                        keysHandle,
                        msgRaw.bindMemory(to: UInt8.self).baseAddress,
                        message.count,
                        pkRaw.bindMemory(to: UInt8.self).baseAddress,
                        nodeAgreementPublicKey.count,
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

    /// Mobile: Decrypt message from node using mobile's agreement private key
    public func mobileDecryptMessageFromNode(encryptedMessage: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.decryptMessageFromNode(encryptedMessage)
    }

    /// Node: Decrypt message from mobile using node's agreement private key
    public func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.decryptMessageFromMobile(encryptedMessage)
    }
}

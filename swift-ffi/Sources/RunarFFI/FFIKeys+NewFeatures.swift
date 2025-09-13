import CRunarFFI
import Foundation

// MARK: - New Features Extension for KeysFFI

@available(macOS 11.0, *)
public extension KeysFFI {
    // MARK: - Node Key Manager Additional Functions

    /// Check if NodeKeyManager has keys
    /// - Returns: true if keys exist, false otherwise
    /// - Throws: FFIError if the operation fails
    func hasKeys() throws -> Bool {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var hasKeys: Int32 = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_node_has_keys(keysHandle, &hasKeys, errPtr)
        }
        if let error = err { throw error }

        return hasKeys != 0
    }

    /// Generate keys for NodeKeyManager
    /// - Throws: FFIError if the operation fails
    func generateKeys() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        let (_, err) = withRnError { errPtr in
            rn_keys_node_generate_keys(keysHandle, errPtr)
        }
        if let error = err { throw error }
    }

    /// Get QUIC certificate configuration
    /// - Returns: CBOR-encoded certificate configuration
    /// - Throws: FFIError if the operation fails
    func getQuicCertificateConfig() throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_quic_certificate_config(keysHandle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Get node certificate
    /// - Returns: DER-encoded certificate
    /// - Throws: FFIError if the operation fails
    func getNodeCertificate() throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_node_certificate(keysHandle, &out, &outLen, errPtr)
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Get certificate status
    /// - Returns: Certificate status information
    /// - Throws: FFIError if the operation fails
    func getCertificateStatus() throws -> Int32 {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var status: Int32 = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_certificate_status(keysHandle, &status, errPtr)
        }
        if let error = err { throw error }

        return status
    }

    /// Get certificate serial number
    /// - Returns: Certificate serial number as hex string
    /// - Throws: FFIError if the operation fails
    func getCertificateSerial() throws -> String {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var out: UnsafeMutablePointer<CChar>?

        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_certificate_serial(keysHandle, &out, errPtr)
        }
        if let error = err { throw error }

        defer { if let outString = out { rn_string_free(outString) } }
        return out.map { String(cString: $0) } ?? ""
    }

    /// Validate peer certificate
    /// - Parameter peerCert: DER-encoded peer certificate
    /// - Throws: FFIError if the operation fails
    func validatePeerCertificate(_ peerCert: Data) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        let (_, err) = withRnError { errPtr in
            peerCert.withUnsafeBytes { raw in
                rn_keys_node_validate_peer_certificate(
                    keysHandle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    peerCert.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
    }

    // MARK: - Profile Key Management

    /// Derive user profile key
    /// - Parameter label: Profile key label
    /// - Returns: Public key data
    /// - Throws: FFIError if the operation fails
    func deriveUserProfileKey(label: String) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            label.withCString { cLabel in
                rn_keys_node_derive_user_profile_key(keysHandle, cLabel, &out, &outLen, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Decrypt envelope data using profile key
    /// - Parameters:
    ///   - envelopeData: CBOR-encoded envelope data
    ///   - profileId: Profile ID for decryption
    /// - Returns: Decrypted data
    /// - Throws: FFIError if the operation fails
    func decryptWithProfile(envelopeData: Data, profileId: String) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            envelopeData.withUnsafeBytes { envelopeRaw in
                profileId.withCString { cProfileId in
                    rn_keys_node_decrypt_with_profile(
                        keysHandle,
                        envelopeRaw.bindMemory(to: UInt8.self).baseAddress,
                        envelopeData.count,
                        cProfileId,
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

    /// Install profile public key
    /// - Parameter publicKey: Public key data
    /// - Throws: FFIError if the operation fails
    func installProfilePublicKey(_ publicKey: Data) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        let (_, err) = withRnError { errPtr in
            publicKey.withUnsafeBytes { raw in
                rn_keys_node_install_profile_public_key(
                    keysHandle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    publicKey.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
    }

    /// Get profile public key by label
    /// - Parameter label: Profile key label
    /// - Returns: Public key data and existence flag
    /// - Throws: FFIError if the operation fails
    func getProfilePublicKeyByLabel(label: String) throws -> (publicKey: Data, hasKey: Bool) {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        var hasKey: Int32 = 0

        let (_, err) = withRnError { errPtr in
            label.withCString { cLabel in
                rn_keys_node_get_profile_public_key_by_label(keysHandle, cLabel, &out, &outLen, &hasKey, errPtr)
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return (Data(), false) }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return (data, hasKey != 0)
    }

    // MARK: - Network Management

    /// Install network key
    /// - Parameter networkKeyMessage: CBOR-encoded network key message
    /// - Throws: FFIError if the operation fails
    func installNetworkKey(_ networkKeyMessage: Data) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        let (_, err) = withRnError { errPtr in
            networkKeyMessage.withUnsafeBytes { raw in
                rn_keys_node_install_network_key(
                    keysHandle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    networkKeyMessage.count,
                    errPtr
                )
            }
        }
        if let error = err { throw error }
    }

    /// Get network agreement
    /// - Parameter networkPublicKey: Network public key
    /// - Returns: Agreement data
    /// - Throws: FFIError if the operation fails
    func getNetworkAgreement(networkPublicKey: Data) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            networkPublicKey.withUnsafeBytes { raw in
                rn_keys_node_get_network_agreement(
                    keysHandle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    networkPublicKey.count,
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

    /// Check if node has network private key
    /// - Parameter networkPublicKey: Network public key
    /// - Returns: true if private key exists, false otherwise
    /// - Throws: FFIError if the operation fails
    func hasNetworkPrivateKey(networkPublicKey: Data) throws -> Bool {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle is null")
        }

        var hasKey: Int32 = 0

        let (_, err) = withRnError { errPtr in
            networkPublicKey.withUnsafeBytes { raw in
                rn_keys_node_has_network_private_key(
                    keysHandle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    networkPublicKey.count,
                    &hasKey,
                    errPtr
                )
            }
        }
        if let error = err { throw error }

        return hasKey != 0
    }

    // MARK: - Utility Functions

    /// Get compact ID for public key
    /// - Parameter publicKey: Public key data
    /// - Returns: Compact ID string
    /// - Throws: FFIError if the operation fails
    func getCompactId(publicKey: Data) throws -> String {
        var out: UnsafeMutablePointer<CChar>?

        let (_, err) = withRnError { errPtr in
            publicKey.withUnsafeBytes { raw in
                rn_keys_get_compact_id(raw.bindMemory(to: UInt8.self).baseAddress, publicKey.count, &out, errPtr)
            }
        }
        if let error = err { throw error }

        defer { if let outString = out { rn_string_free(outString) } }
        return out.map { String(cString: $0) } ?? ""
    }
}

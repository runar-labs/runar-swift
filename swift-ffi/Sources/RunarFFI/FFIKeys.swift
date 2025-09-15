import CRunarFFI
import Foundation
import os

/// Swift FFI Keys Manager - mirrors Rust KeysInner structure
@available(macOS 11.0, *)
public final class KeysFFI {
    let logger: Logger
    var mobileKeyManager: MobileKeyManager?
    var nodeKeyManager: NodeKeyManager?
    private var labelResolver: LabelResolver?
    private var localNodeInfo: Atomic<RunarFFINodeInfo?>
    private var deviceKeystore: DeviceKeystore?
    private var persistenceDir: URL?
    private var autoPersist: Bool
    var handle: UnsafeMutableRawPointer?

    /// Get the raw FFI handle (for compatibility with other classes)
    public var rawHandle: UnsafeMutableRawPointer? {
        handle
    }

    public init(logger: Logger? = nil) throws {
        if let logger {
            self.logger = logger
        } else {
            self.logger = SimpleLogger()
        }
        localNodeInfo = Atomic<RunarFFINodeInfo?>(nil)
        autoPersist = false

        // Initialize the underlying FFI handle
        var out: UnsafeMutableRawPointer?
        let (result, error) = withRnError { errPtr in
            rn_keys_new(&out, errPtr)
        }
        guard result == 0, let keysHandle = out else {
            throw error ?? FFIError.operationFailed("Failed to create keys handle")
        }
        handle = keysHandle
    }

    deinit {
        if let keysHandle = handle {
            rn_keys_free(keysHandle)
        }
    }

    // MARK: - Initialization Functions

    public func initializeAsMobile() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        guard mobileKeyManager == nil else {
            throw FFIError.wrongManagerType("Already initialized as mobile")
        }

        // Call the Rust FFI to initialize
        let (_, error) = withRnError { errPtr in
            rn_keys_init_as_mobile(keysHandle, errPtr)
        }
        if let error { throw error }

        let manager = MobileKeyManagerImpl(handle: keysHandle, logger: logger)
        mobileKeyManager = manager
        nodeKeyManager = nil

        logger.info("Initialized as mobile key manager via FFI")
    }

    public func initializeAsNode() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        guard nodeKeyManager == nil else {
            throw FFIError.wrongManagerType("Already initialized as node")
        }

        // Call the Rust FFI to initialize
        let (_, error) = withRnError { errPtr in
            rn_keys_init_as_node(keysHandle, errPtr)
        }
        if let error { throw error }

        let manager = NodeKeyManagerImpl(handle: keysHandle, logger: logger)
        nodeKeyManager = manager
        mobileKeyManager = nil

        logger.info("Initialized as node key manager via FFI")
    }

    func validateMobileManager() throws -> MobileKeyManager {
        guard let manager = mobileKeyManager else {
            throw FFIError.notInitialized
        }
        return manager
    }

    func validateNodeManager() throws -> NodeKeyManager {
        guard let manager = nodeKeyManager else {
            throw FFIError.notInitialized
        }
        return manager
    }

    // MARK: - Public Node Key Manager Delegation Methods

    /// Generate CSR (Certificate Signing Request)
    /// - Returns: CBOR-encoded SetupToken containing CSR
    /// - Throws: FFIError if the operation fails
    public func generateCSR() throws -> Data {
        let manager = try validateNodeManager()
        return try manager.generateCSR()
    }

    /// Install certificate from enrollment/renewal response
    /// - Parameter nodeCertificateMessageCBOR: CBOR-encoded certificate message
    /// - Throws: FFIError if the operation fails
    public func installCertificate(_ nodeCertificateMessageCBOR: Data) throws {
        let manager = try validateNodeManager()
        try manager.installCertificate(nodeCertificateMessageCBOR)
    }

    /// Get node certificate
    /// - Returns: DER-encoded certificate
    /// - Throws: FFIError if the operation fails
    public func getNodeCertificate() throws -> Data {
        let manager = try validateNodeManager()
        return try manager.getNodeCertificate()
    }

    /// Derive user profile key
    /// - Parameter label: Profile key label
    /// - Returns: Public key data
    /// - Throws: FFIError if the operation fails
    public func deriveUserProfileKey(label: String) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.deriveUserProfileKey(label: label)
    }

    /// Encrypt data with envelope encryption
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - networkPublicKey: Network public key (optional)
    ///   - profileKeys: Array of profile keys (optional)
    /// - Returns: Encrypted envelope data
    /// - Throws: FFIError if the operation fails
    public func encryptWithEnvelope(data: Data, networkPublicKey: Data? = nil, profileKeys: [Data]? = nil) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.encryptWithEnvelope(data: data, networkPublicKey: networkPublicKey, profileKeys: profileKeys)
    }

    /// Decrypt envelope data using profile key
    /// - Parameters:
    ///   - envelopeData: Encrypted envelope data
    ///   - profileId: Profile ID for decryption
    /// - Returns: Decrypted data
    /// - Throws: FFIError if the operation fails
    public func decryptWithProfile(envelopeData: Data, profileId: String) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.decryptWithProfile(envelopeData: envelopeData, profileId: profileId)
    }

    /// Get QUIC certificate configuration
    /// - Returns: QUIC certificate configuration data
    /// - Throws: FFIError if the operation fails
    public func getQuicCertificateConfig() throws -> Data {
        let manager = try validateNodeManager()
        return try manager.getQuicCertificateConfig()
    }

    // MARK: - Public Mobile Key Manager Delegation Methods

    /// Convert enrollment response to certificate message
    /// - Parameter response: Enrollment response data
    /// - Returns: Certificate message data
    /// - Throws: FFIError if the operation fails
    public func fromEnrollResponse(_ response: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.fromEnrollResponse(response)
    }

    /// Convert renewal response to certificate message
    /// - Parameter response: Renewal response data
    /// - Returns: Certificate message data
    /// - Throws: FFIError if the operation fails
    public func fromRenewResponse(_ response: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.fromRenewResponse(response)
    }

    // MARK: - Direct FFI Functions

    /// Get the last error message from the FFI
    public func getLastError() -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        let result = rn_last_error(&buffer, buffer.count)
        if result == 0 {
            let nullTerminatedBuffer = buffer.prefix(while: { $0 != 0 })
            return String(cString: Array(nullTerminatedBuffer) + [0])
        }
        return "Failed to retrieve error message"
    }


    /// Set local NodeInfo from CBOR buffer
    public func setLocalNodeInfo(_ nodeInfoCBOR: Data) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let result = nodeInfoCBOR.withUnsafeBytes { raw in
            rn_keys_set_local_node_info(keysHandle, raw.bindMemory(to: UInt8.self).baseAddress, nodeInfoCBOR.count)
        }
        if result != 0 {
            let errorMessage = getLastError()
            throw FFIError.operationFailed(
                "Failed to set local node info (error code: \(result), message: \(errorMessage))")
        }
    }

    /// Set persistence directory
    public func setPersistenceDirectory(_ directory: URL) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let (_, error) = withRnError { errPtr in
            directory.path.withCString { cDir in
                rn_keys_set_persistence_dir(keysHandle, cDir, errPtr)
            }
        }
        if let error { throw error }
    }

    /// Enable auto persist
    public func enableAutoPersist(_ enabled: Bool) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let (_, error) = withRnError { errPtr in
            rn_keys_enable_auto_persist(keysHandle, enabled, errPtr)
        }
        if let error { throw error }
    }

    /// Wipe persistence
    public func wipePersistence() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let (_, error) = withRnError { errPtr in
            rn_keys_wipe_persistence(keysHandle, errPtr)
        }
        if let error { throw error }
    }

    /// Get keystore capabilities
    public func getKeystoreCaps() throws -> RNAPIRnDeviceKeystoreCaps {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        var caps = RNAPIRnDeviceKeystoreCaps()
        let (_, error) = withRnError { errPtr in
            rn_keys_get_keystore_caps(keysHandle, &caps, errPtr)
        }
        if let error { throw error }

        return caps
    }

    /// Flush state
    public func flushState() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let (_, error) = withRnError { errPtr in
            rn_keys_flush_state(keysHandle, errPtr)
        }
        if let error { throw error }
    }

    /// Ensure symmetric key exists
    public func ensureSymmetricKey(_ keyName: String) throws -> Data {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, error) = withRnError { errPtr in
            keyName.withCString { cKeyName in
                rn_keys_ensure_symmetric_key(keysHandle, cKeyName, &out, &outLen, errPtr)
            }
        }
        if let error { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    // MARK: - Additional Encryption Functions

    /// Encrypt data for a specific public key
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
        if let error { throw error }

        guard let outPtr = out else { return Data() }
        let result = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return result
    }

    /// Encrypt data for a specific network
    public func encryptForNetwork(data: Data, networkPublicKey: Data) throws -> Data {
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

    /// Get compact ID for a public key
    /// - Parameter publicKey: Public key data
    /// - Returns: Compact ID string
    /// - Throws: FFIError if the operation fails
    public func getCompactId(publicKey: Data) throws -> String {
        let manager = try validateNodeManager()
        return try manager.getCompactId(publicKey: publicKey)
    }

    /// Decrypt network data
    public func decryptNetworkData(eedCbor: Data) throws -> Data {
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

}

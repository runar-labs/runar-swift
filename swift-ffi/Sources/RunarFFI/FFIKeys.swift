import CRunarFFI
import Foundation
import os

// MARK: - Type Definitions

/// Node Info structure for FFI
public struct RunarFFINodeInfo {
    public let nodeId: String
    public let publicKey: Data
}

/// Atomic wrapper for thread-safe access
public final class Atomic<T> {
    private var value: T
    private let lock = NSLock()

    public init(_ value: T) {
        self.value = value
    }

    public func load() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func store(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

// MARK: - Protocols

/// Mobile Key Manager - mirrors Rust MobileKeyManager
public protocol MobileKeyManager {
    func initializeUserRootKey() throws
    func getUserPublicKey() throws -> Data
    func processSetupToken(setupTokenCBOR: Data) throws -> Data
    func registerDeviceKeystore(_ keystore: DeviceKeystore) throws
    func setPersistenceDirectory(_ directory: URL) throws
    func enableAutoPersist(_ enabled: Bool) throws
    func getKeystoreState() throws -> Int32
    func generateNetworkDataKey() throws -> String
    func getNetworkPublicKey(_ networkId: String) throws -> Data
    func createNetworkKeyMessage(networkId: String, nodeAgreementPk: Data) throws -> Data
    func deriveUserProfileKey(label: String) throws -> Data
    func encryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data
    func encryptLocalData(_ data: Data) throws -> Data
    func decryptLocalData(_ encrypted: Data) throws -> Data

    // Add these missing functions
    func decryptMessageFromNode(encryptedMessage: Data) throws -> Data
    func decryptEnvelope(eedCbor: Data) throws -> Data
    func installNetworkPublicKey(networkPublicKey: Data) throws

    // REMOVE these non-existent functions:
    // func generateCSR() throws -> Data  // ❌ DOES NOT EXIST IN RUST FFI
    // func installCertificate(_ nodeCertificateMessageCBOR: Data) throws  // ❌ DOES NOT EXIST IN RUST FFI
}

/// Node Key Manager - mirrors Rust NodeKeyManager
public protocol NodeKeyManager {
    func getPublicKey() throws -> Data
    func getAgreementPublicKey() throws -> Data
    func generateCSR() throws -> Data
    func installCertificate(_ nodeCertificateMessageCBOR: Data) throws
    func registerDeviceKeystore(_ keystore: DeviceKeystore) throws
    func setPersistenceDirectory(_ directory: URL) throws
    func enableAutoPersist(_ enabled: Bool) throws
    func getKeystoreState() throws -> Int32
    func installNetworkKey(_ nkmCbor: Data) throws
    func encryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data
    func encryptLocalData(_ data: Data) throws -> Data
    func decryptLocalData(_ encrypted: Data) throws -> Data

    // Add these missing functions
    func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data
    func decryptEnvelope(eedCbor: Data) throws -> Data
    func getNodeId() throws -> String
}

/// Label Resolver for key derivation
public protocol LabelResolver {
    func resolveLabel(_ label: String) throws -> String
}

/// Device Keystore abstraction
public protocol DeviceKeystore {
    func storeKey(_ key: Data, label: String) throws
    func retrieveKey(label: String) throws -> Data?
    func deleteKey(label: String) throws
}

/// Swift FFI Keys Manager - mirrors Rust KeysInner structure
@available(macOS 11.0, *)
public final class KeysFFI {
    private let logger: Logger
    private var mobileKeyManager: MobileKeyManager?
    private var nodeKeyManager: NodeKeyManager?
    private var labelResolver: LabelResolver?
    private var localNodeInfo: Atomic<RunarFFINodeInfo?>
    private var deviceKeystore: DeviceKeystore?
    private var persistenceDir: URL?
    private var autoPersist: Bool
    private var handle: UnsafeMutableRawPointer?

    /// Get the raw FFI handle (for compatibility with other classes)
    public var rawHandle: UnsafeMutableRawPointer? {
        return handle
    }

    public init(logger: Logger? = nil) {
        if let logger = logger {
            self.logger = logger
        } else {
            self.logger = Logger(subsystem: "com.runar.ffi", category: "keys")
        }
        localNodeInfo = Atomic<RunarFFINodeInfo?>(nil)
        autoPersist = false

        // Initialize the underlying FFI handle
        var out: UnsafeMutableRawPointer?
        let result = rn_keys_new(&out, nil)
        if result == 0 {
            handle = out
        } else {
            print("Failed to create keys handle")
        }
    }

    deinit {
        if let h = handle {
            rn_keys_free(h)
        }
    }

    // MARK: - Initialization Functions

    public func initializeAsMobile() throws {
        guard let h = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        guard mobileKeyManager == nil else {
            throw FFIError.wrongManagerType("Already initialized as mobile")
        }

        let manager = MobileKeyManagerImpl(handle: h, logger: logger)
        mobileKeyManager = manager
        nodeKeyManager = nil

        logger.info("Initialized as mobile key manager")
    }

    public func initializeAsNode() throws {
        guard let h = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        guard nodeKeyManager == nil else {
            throw FFIError.wrongManagerType("Already initialized as node")
        }

        let manager = NodeKeyManagerImpl(handle: h, logger: logger)
        nodeKeyManager = manager
        mobileKeyManager = nil

        logger.info("Initialized as node key manager")
    }

    // MARK: - FFI Initialization Functions

    /// Initialize FFI instance as mobile manager using Rust FFI
        public func keysInitAsMobile() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        let (_, error) = withRnError { errPtr in
            rn_keys_init_as_mobile(keysHandle, errPtr)
        }
        if let error = error { throw error }
        
        // Update internal state
        let manager = MobileKeyManagerImpl(handle: keysHandle, logger: logger)
        mobileKeyManager = manager
        nodeKeyManager = nil
        
        logger.info("Initialized as mobile key manager via FFI")
    }

    /// Initialize FFI instance as node manager using Rust FFI
        public func keysInitAsNode() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        let (_, error) = withRnError { errPtr in
            rn_keys_init_as_node(keysHandle, errPtr)
        }
        if let error = error { throw error }
        
        // Update internal state
        let manager = NodeKeyManagerImpl(handle: keysHandle, logger: logger)
        nodeKeyManager = manager
        mobileKeyManager = nil
        
        logger.info("Initialized as node key manager via FFI")
    }

    private func validateMobileManager() throws -> MobileKeyManager {
        guard let manager = mobileKeyManager else {
            throw FFIError.notInitialized
        }
        return manager
    }

    private func validateNodeManager() throws -> NodeKeyManager {
        guard let manager = nodeKeyManager else {
            throw FFIError.notInitialized
        }
        return manager
    }

    // MARK: - API Functions

    /// Mobile: Initialize user root key
    public func mobileInitializeUserRootKey() throws {
        let manager = try validateMobileManager()
        try manager.initializeUserRootKey()
    }

    /// Mobile: Get user public key
    public func mobileGetUserPublicKey() throws -> Data {
        let manager = try validateMobileManager()
        return try manager.getUserPublicKey()
    }

    // REMOVED: mobileGenerateCSR() - This function does not exist in the Rust FFI API

    /// Mobile: Process setup token
    public func mobileProcessSetupToken(_ setupTokenCBOR: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.processSetupToken(setupTokenCBOR: setupTokenCBOR)
    }

    // REMOVED: mobileInstallCertificate() - This function does not exist in the Rust FFI API

    /// Mobile: Register device keystore
    public func mobileRegisterDeviceKeystore(_: DeviceKeystore) throws {
        // This is now handled by the platform-specific registration functions above
        // The DeviceKeystore protocol is kept for compatibility but actual registration
        // goes through the FFI functions
        logger.info("Device keystore registration handled by platform-specific functions")
    }

    /// Mobile: Set persistence directory
    public func mobileSetPersistenceDirectory(_ directory: URL) throws {
        let manager = try validateMobileManager()
        try manager.setPersistenceDirectory(directory)
    }

    /// Mobile: Enable auto persist
    public func mobileEnableAutoPersist(_ enabled: Bool) throws {
        let manager = try validateMobileManager()
        try manager.enableAutoPersist(enabled)
    }

    /// Mobile: Get keystore state
    public func mobileGetKeystoreState() throws -> Int32 {
        let manager = try validateMobileManager()
        return try manager.getKeystoreState()
    }

    /// Mobile: Generate network data key
    public func mobileGenerateNetworkDataKey() throws -> String {
        let manager = try validateMobileManager()
        return try manager.generateNetworkDataKey()
    }

    /// Mobile: Get network public key
    public func mobileGetNetworkPublicKey(_ networkId: String) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.getNetworkPublicKey(networkId)
    }

    /// Mobile: Create network key message
    public func mobileCreateNetworkKeyMessage(networkId: String, nodeAgreementPk: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.createNetworkKeyMessage(networkId: networkId, nodeAgreementPk: nodeAgreementPk)
    }

    /// Mobile: Derive user profile key
    public func mobileDeriveUserProfileKey(label: String) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.deriveUserProfileKey(label: label)
    }

    /// Mobile: Encrypt with envelope
    public func mobileEncryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.encryptWithEnvelope(data: data, networkId: networkId, profileKeys: profileKeys)
    }

    /// Mobile: Encrypt local data
    public func mobileEncryptLocalData(_ data: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.encryptLocalData(data)
    }

    /// Mobile: Decrypt local data
    public func mobileDecryptLocalData(_ encrypted: Data) throws -> Data {
        let manager = try validateMobileManager()
        return try manager.decryptLocalData(encrypted)
    }

    /// Node: Get public key
    public func nodeGetPublicKey() throws -> Data {
        let manager = try validateNodeManager()
        return try manager.getPublicKey()
    }

    /// Node: Get agreement public key
    public func nodeGetAgreementPublicKey() throws -> Data {
        let manager = try validateNodeManager()
        return try manager.getAgreementPublicKey()
    }

    /// Node: Generate CSR
    public func nodeGenerateCSR() throws -> Data {
        let manager = try validateNodeManager()
        return try manager.generateCSR()
    }

    /// Node: Install certificate
    public func nodeInstallCertificate(_ nodeCertificateMessageCBOR: Data) throws {
        let manager = try validateNodeManager()
        try manager.installCertificate(nodeCertificateMessageCBOR)
    }

    /// Node: Register device keystore
    public func nodeRegisterDeviceKeystore(_: DeviceKeystore) throws {
        // This is now handled by the platform-specific registration functions above
        // The DeviceKeystore protocol is kept for compatibility but actual registration
        // goes through the FFI functions
        logger.info("Device keystore registration handled by platform-specific functions")
    }

    /// Node: Set persistence directory
    public func nodeSetPersistenceDirectory(_ directory: URL) throws {
        let manager = try validateNodeManager()
        try manager.setPersistenceDirectory(directory)
    }

    /// Node: Enable auto persist
    public func nodeEnableAutoPersist(_ enabled: Bool) throws {
        let manager = try validateNodeManager()
        try manager.enableAutoPersist(enabled)
    }

    /// Node: Get keystore state
    public func nodeGetKeystoreState() throws -> Int32 {
        let manager = try validateNodeManager()
        return try manager.getKeystoreState()
    }

    /// Node: Install network key
    public func nodeInstallNetworkKey(_ nkmCbor: Data) throws {
        let manager = try validateNodeManager()
        try manager.installNetworkKey(nkmCbor)
    }

    /// Node: Encrypt with envelope
    public func nodeEncryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.encryptWithEnvelope(data: data, networkId: networkId, profileKeys: profileKeys)
    }

    /// Node: Encrypt local data
    public func nodeEncryptLocalData(_ data: Data) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.encryptLocalData(data)
    }

    /// Node: Decrypt local data
    public func nodeDecryptLocalData(_ encrypted: Data) throws -> Data {
        let manager = try validateNodeManager()
        return try manager.decryptLocalData(encrypted)
    }

    /// Set label mapping
    public func setLabelMapping(_ mappingCBOR: Data) throws {
        guard let h = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        let result = mappingCBOR.withUnsafeBytes { raw in
            rn_keys_set_label_mapping(h, raw.bindMemory(to: UInt8.self).baseAddress, mappingCBOR.count)
        }
        if result != 0 {
            throw FFIError.operationFailed("Failed to set label mapping")
        }
    }

    /// Set local node info
    public func setLocalNodeInfo(_ nodeInfoCBOR: Data) throws {
        guard let h = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        let result = nodeInfoCBOR.withUnsafeBytes { raw in
            rn_keys_set_local_node_info(h, raw.bindMemory(to: UInt8.self).baseAddress, nodeInfoCBOR.count)
        }
        if result != 0 {
            throw FFIError.operationFailed("Failed to set local node info")
        }
    }

    /// Create new keys handle (static function for compatibility)
    public static func keysNew() throws -> KeysFFI {
        return KeysFFI()
    }

    // MARK: - Message Encryption Functions

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
        guard let h = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            message.withUnsafeBytes { msgRaw in
                nodeAgreementPublicKey.withUnsafeBytes { pkRaw in
                    rn_keys_encrypt_message_for_node(
                        h,
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
        if let e = err { throw e }

        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
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

// MARK: - Manager Implementations

/// Mobile Key Manager implementation using FFI
@available(macOS 11.0, *)
private final class MobileKeyManagerImpl: MobileKeyManager {
    private let handle: UnsafeMutableRawPointer
    private let logger: Logger

    @available(macOS 11.0, *)
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

    // REMOVE these non-existent functions:
    // func generateCSR() throws -> Data  // ❌ DOES NOT EXIST IN RUST FFI
    // func installCertificate(_ nodeCertificateMessageCBOR: Data) throws  // ❌ DOES NOT EXIST IN RUST FFI

    func processSetupToken(setupTokenCBOR: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            setupTokenCBOR.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt8.self).baseAddress
                rn_keys_mobile_process_setup_token(handle, p, setupTokenCBOR.count, &out, &outLen, errPtr)
            }
        }
        if let e = err { throw e }
        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return data
    }

    // REMOVED: func installCertificate(_ nodeCertificateMessageCBOR: Data) throws
    // This function does not exist in the Rust FFI API

    func registerDeviceKeystore(_: DeviceKeystore) throws {
        // Implementation depends on keystore type
        logger.info("Registering device keystore")
    }

    func setPersistenceDirectory(_ directory: URL) throws {
        let result = directory.path.withCString { cDir in
            rn_keys_set_persistence_dir(handle, cDir, nil)
        }
        if result != 0 {
            throw FFIError.operationFailed("Failed to set persistence directory")
        }
    }

    func enableAutoPersist(_ enabled: Bool) throws {
        let (_, err) = withRnError { errPtr in
            rn_keys_enable_auto_persist(handle, enabled, errPtr)
        }
        if let e = err { throw e }
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
        var nidCStr: UnsafeMutablePointer<CChar>?
        var nidLen = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_generate_network_data_key(handle, &nidCStr, &nidLen, errPtr)
        }
        if let e = err { throw e }
        defer { if let c = nidCStr { rn_string_free(c) } }
        return nidCStr.map { String(cString: $0) } ?? ""
    }

    func getNetworkPublicKey(_ networkId: String) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            networkId.withCString { cNid in
                rn_keys_mobile_get_network_public_key(handle, cNid, &out, &outLen, errPtr)
            }
        }
        if let e = err { throw e }
        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return data
    }

    func createNetworkKeyMessage(networkId: String, nodeAgreementPk: Data) throws -> Data {
        var outCbor: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            networkId.withCString { nidC in
                nodeAgreementPk.withUnsafeBytes { pkRaw in
                    let pkPtr = pkRaw.bindMemory(to: UInt8.self).baseAddress
                    rn_keys_mobile_create_network_key_message(handle, nidC, pkPtr, nodeAgreementPk.count, &outCbor, &outLen, errPtr)
                }
            }
        }
        if let e = err { throw e }
        guard let b = outCbor else { return Data() }
        let data = Data(bytes: b, count: outLen)
        rn_free(b, outLen)
        return data
    }

    func deriveUserProfileKey(label: String) throws -> Data {
        var outPk: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            label.withCString { cLabel in
                rn_keys_mobile_derive_user_profile_key(handle, cLabel, &outPk, &outLen, errPtr)
            }
        }
        if let e = err { throw e }
        guard let b = outPk else { return Data() }
        let data = Data(bytes: b, count: outLen)
        rn_free(b, outLen)
        return data
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

    func encryptLocalData(_ data: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let result = data.withUnsafeBytes { raw in
            rn_keys_encrypt_local_data(handle,
                                       raw.bindMemory(to: UInt8.self).baseAddress,
                                       data.count,
                                       &out,
                                       &outLen,
                                       nil)
        }
        if result != 0 {
            throw FFIError.operationFailed("Failed to encrypt local data")
        }
        guard let p = out else { return Data() }
        let cipher = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return cipher
    }

    func decryptLocalData(_ encrypted: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let result = encrypted.withUnsafeBytes { raw in
            rn_keys_decrypt_local_data(handle,
                                       raw.bindMemory(to: UInt8.self).baseAddress,
                                       encrypted.count,
                                       &out,
                                       &outLen,
                                       nil)
        }
        if result != 0 {
            throw FFIError.operationFailed("Failed to decrypt local data")
        }
        guard let p = out else { return Data() }
        let plain = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return plain
    }
}

/// Node Key Manager implementation using FFI
@available(macOS 11.0, *)
private final class NodeKeyManagerImpl: NodeKeyManager {
    private let handle: UnsafeMutableRawPointer
    private let logger: Logger

    @available(macOS 11.0, *)
    init(handle: UnsafeMutableRawPointer, logger: Logger) {
        self.handle = handle
        self.logger = logger
    }

    func getPublicKey() throws -> Data {
        var buf: UnsafeMutablePointer<UInt8>?
        var len = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_public_key(handle, &buf, &len, errPtr)
        }
        if let e = err { throw e }
        guard let b = buf else { return Data() }
        let data = Data(bytes: b, count: len)
        rn_free(b, len)
        return data
    }

    func getAgreementPublicKey() throws -> Data {
        var buf: UnsafeMutablePointer<UInt8>?
        var len = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_agreement_public_key(handle, &buf, &len, errPtr)
        }
        if let e = err { throw e }
        guard let b = buf else { return Data() }
        let data = Data(bytes: b, count: len)
        rn_free(b, len)
        return data
    }

    func generateCSR() throws -> Data {
        var buf: UnsafeMutablePointer<UInt8>?
        var len = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_generate_csr(handle, &buf, &len, errPtr)
        }
        if let e = err { throw e }
        guard let b = buf else { return Data() }
        let data = Data(bytes: b, count: len)
        rn_free(b, len)
        return data
    }

    func installCertificate(_ nodeCertificateMessageCBOR: Data) throws {
        let (_, err) = withRnError { errPtr in
            nodeCertificateMessageCBOR.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt8.self).baseAddress
                rn_keys_node_install_certificate(handle, p, nodeCertificateMessageCBOR.count, errPtr)
            }
        }
        if let e = err { throw e }
    }

    func registerDeviceKeystore(_: DeviceKeystore) throws {
        // Implementation depends on keystore type
        logger.info("Registering device keystore")
    }

    func setPersistenceDirectory(_ directory: URL) throws {
        let result = directory.path.withCString { cDir in
            rn_keys_set_persistence_dir(handle, cDir, nil)
        }
        if result != 0 {
            throw FFIError.operationFailed("Failed to set persistence directory")
        }
    }

    func enableAutoPersist(_ enabled: Bool) throws {
        let (_, err) = withRnError { errPtr in
            rn_keys_enable_auto_persist(handle, enabled, errPtr)
        }
        if let e = err { throw e }
    }

    func getKeystoreState() throws -> Int32 {
        var state: Int32 = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_keystore_state(handle, &state, errPtr)
        }
        if let e = err { throw e }
        return state
    }

    func installNetworkKey(_ nkmCbor: Data) throws {
        let (_, err) = withRnError { errPtr in
            nkmCbor.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt8.self).baseAddress
                rn_keys_node_install_network_key(handle, p, nkmCbor.count, errPtr)
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
                            rn_keys_node_encrypt_with_envelope(
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
                        rn_keys_node_encrypt_with_envelope(
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

    func encryptLocalData(_ data: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let result = data.withUnsafeBytes { raw in
            rn_keys_encrypt_local_data(handle,
                                       raw.bindMemory(to: UInt8.self).baseAddress,
                                       data.count,
                                       &out,
                                       &outLen,
                                       nil)
        }
        if result != 0 {
            throw FFIError.operationFailed("Failed to encrypt local data")
        }
        guard let p = out else { return Data() }
        let cipher = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return cipher
    }

    func decryptLocalData(_ encrypted: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let result = encrypted.withUnsafeBytes { raw in
            rn_keys_decrypt_local_data(handle,
                                       raw.bindMemory(to: UInt8.self).baseAddress,
                                       encrypted.count,
                                       &out,
                                       &outLen,
                                       nil)
        }
        if result != 0 {
            throw FFIError.operationFailed("Failed to decrypt local data")
        }
        guard let p = out else { return Data() }
        let plain = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return plain
    }

    // Add these missing functions
    func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            encryptedMessage.withUnsafeBytes { msgRaw in
                rn_keys_decrypt_message_from_mobile(
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
                rn_keys_node_decrypt_envelope(
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

    func getNodeId() throws -> String {
        var outStr: UnsafeMutablePointer<CChar>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_node_id(handle, &outStr, &outLen, errPtr)
        }
        if let e = err { throw e }

        defer { if let s = outStr { rn_string_free(s) } }
        return outStr.map { String(cString: $0) } else { "" }
    }
}

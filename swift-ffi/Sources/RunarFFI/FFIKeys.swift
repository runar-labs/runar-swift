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
        if let error = error { throw error }

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
        if let error = error { throw error }

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

    // MARK: - Direct FFI Functions

    /// Set label mapping from CBOR buffer
    public func setLabelMapping(_ mappingCBOR: Data) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let result = mappingCBOR.withUnsafeBytes { raw in
            rn_keys_set_label_mapping(keysHandle, raw.bindMemory(to: UInt8.self).baseAddress, mappingCBOR.count)
        }
        if result != 0 {
            throw FFIError.operationFailed("Failed to set label mapping")
        }
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
            throw FFIError.operationFailed("Failed to set local node info")
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
        if let error = error { throw error }
    }

    /// Enable auto persist
    public func enableAutoPersist(_ enabled: Bool) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let (_, error) = withRnError { errPtr in
            rn_keys_enable_auto_persist(keysHandle, enabled, errPtr)
        }
        if let error = error { throw error }
    }

    /// Wipe persistence
    public func wipePersistence() throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let (_, error) = withRnError { errPtr in
            rn_keys_wipe_persistence(keysHandle, errPtr)
        }
        if let error = error { throw error }
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
        if let error = error { throw error }

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
        if let error = error { throw error }
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
        if let error = error { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }
}

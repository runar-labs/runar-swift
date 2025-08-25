# **Swift FFI Key Management Refactoring - Design Document**

## **🎯 OBJECTIVE**
Complete redesign of the Swift FFI key management system to align with the latest Rust FFI architecture. This ensures seamless integration, eliminates decision logic, removes code duplication, and maintains clear separation between mobile and node key managers while following Apple's platform best practices.

## **📋 COMPREHENSIVE GAP ANALYSIS: Swift FFI vs Rust FFI API**

Based on detailed analysis of the current Swift FFI implementation versus the latest Rust FFI API, here are the **CRITICAL GAPS** that need to be addressed:

### **🚨 MISSING FUNCTIONS (NOT IMPLEMENTED IN SWIFT)**

#### **1. Core Initialization Functions**
- ❌ `rn_keys_init_as_mobile()` - **CRITICAL MISSING**
- ❌ `rn_keys_init_as_node()` - **CRITICAL MISSING**

#### **2. Message Encryption Functions**
- ❌ `rn_keys_encrypt_message_for_mobile()` - **CRITICAL MISSING**
- ❌ `rn_keys_encrypt_message_for_node()` - **CRITICAL MISSING**
- ❌ `rn_keys_mobile_decrypt_message_from_node()` - **CRITICAL MISSING**
- ❌ `rn_keys_decrypt_message_from_mobile()` - **CRITICAL MISSING**

#### **3. Envelope Decryption Functions**
- ❌ `rn_keys_node_decrypt_envelope()` - **CRITICAL MISSING**
- ❌ `rn_keys_mobile_decrypt_envelope()` - **CRITICAL MISSING**

#### **4. Network & Profile Key Functions**
- ❌ `rn_keys_mobile_install_network_public_key()` - **CRITICAL MISSING**

#### **5. Additional Encryption Functions**
- ❌ `rn_keys_encrypt_for_public_key()` - **CRITICAL MISSING**
- ❌ `rn_keys_encrypt_for_network()` - **CRITICAL MISSING**
- ❌ `rn_keys_decrypt_network_data()` - **CRITICAL MISSING**
- ❌ `rn_keys_ensure_symmetric_key()` - **CRITICAL MISSING**

#### **6. Node Identity Functions**
- ❌ `rn_keys_node_get_node_id()` - **CRITICAL MISSING**

#### **7. Utility Functions**
- ❌ `rn_keys_flush_state()` - **CRITICAL MISSING**
- ❌ `rn_keys_get_keystore_caps()` - **CRITICAL MISSING**
- ❌ `rn_keys_wipe_persistence()` - **CRITICAL MISSING**

### **🔧 PARTIALLY IMPLEMENTED FUNCTIONS (NEED UPDATES)**

#### **1. Device Keystore Registration**
- ⚠️ `rn_keys_register_apple_device_keystore()` - **PLACEHOLDER ONLY** - Must implement Apple Keychain integration
- ⚠️ `rn_keys_register_linux_device_keystore()` - **PLACEHOLDER ONLY** - Must implement Linux keyring integration

#### **2. Apple-Specific Functions (CRITICAL FOR SWIFT)**
The Swift FFI implementation **MUST** implement these Apple-specific functions as they are essential for iOS/macOS integration:

- ⚠️ `rn_keys_register_apple_device_keystore()` - **MUST IMPLEMENT** Apple Keychain/Secure Enclave integration
- ⚠️ `rn_keys_get_keystore_caps()` - **MUST IMPLEMENT** to get device keystore capabilities
- ⚠️ `rn_keys_wipe_persistence()` - **MUST IMPLEMENT** for secure data cleanup
- ⚠️ `rn_keys_flush_state()` - **MUST IMPLEMENT** for state persistence

### **🗑️ DEPRECATED/REMOVED FUNCTIONS (MUST BE CLEANED UP)**

#### **1. Non-Existent Mobile Functions**
- ❌ `rn_keys_mobile_generate_csr()` - **DOES NOT EXIST IN RUST FFI** - Must be removed
- ❌ `rn_keys_mobile_install_certificate()` - **DOES NOT EXIST IN RUST FFI** - Must be removed

#### **2. Impact of Deprecated Functions**
These functions were implemented in Swift but **never existed** in the Rust FFI API:
- They create confusion and false expectations
- They cannot be tested or validated
- They represent technical debt and misalignment
- They must be **completely removed** from Swift FFI

### **✅ CORRECTLY IMPLEMENTED FUNCTIONS**

#### **1. Core Functions**
- ✅ `rn_keys_new()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_free()` - **CORRECTLY IMPLEMENTED**

#### **2. Key Management Functions**
- ✅ `rn_keys_mobile_initialize_user_root_key()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_mobile_get_user_public_key()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_node_get_public_key()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_node_get_agreement_public_key()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_node_generate_csr()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_mobile_process_setup_token()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_node_install_certificate()` - **CORRECTLY IMPLEMENTED**

#### **3. Network Key Functions**
- ✅ `rn_keys_mobile_generate_network_data_key()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_mobile_get_network_public_key()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_mobile_create_network_key_message()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_node_install_network_key()` - **CORRECTLY IMPLEMENTED**

#### **4. Profile Key Functions**
- ✅ `rn_keys_mobile_derive_user_profile_key()` - **CORRECTLY IMPLEMENTED**

#### **5. Envelope Encryption Functions**
- ✅ `rn_keys_node_encrypt_with_envelope()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_mobile_encrypt_with_envelope()` - **CORRECTLY IMPLEMENTED**

#### **6. Local Data Functions**
- ✅ `rn_keys_encrypt_local_data()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_decrypt_local_data()` - **CORRECTLY IMPLEMENTED**

#### **7. Persistence Functions**
- ✅ `rn_keys_set_persistence_dir()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_enable_auto_persist()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_node_get_keystore_state()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_mobile_get_keystore_state()` - **CORRECTLY IMPLEMENTED**

#### **8. Utility Functions**
- ✅ `rn_keys_set_label_mapping()` - **CORRECTLY IMPLEMENTED**
- ✅ `rn_keys_set_local_node_info()` - **CORRECTLY IMPLEMENTED**

#### **9. Transport Functions**
- ✅ **ALL TRANSPORT FUNCTIONS** - **CORRECTLY IMPLEMENTED**

#### **10. Discovery Functions**
- ✅ **ALL DISCOVERY FUNCTIONS** - **CORRECTLY IMPLEMENTED**

## **📋 LATEST RUST API ANALYSIS**

Based on the latest Rust FFI header (`runar_ffi.h`), the following functions are available:

### **Core Functions (Already Analyzed):**
- ✅ `rn_keys_new()` - Create keys handle
- ✅ `rn_keys_init_as_mobile()` - Initialize as mobile
- ✅ `rn_keys_init_as_node()` - Initialize as node
- ✅ `rn_keys_mobile_initialize_user_root_key()` - Initialize user root key
- ✅ `rn_keys_mobile_get_user_public_key()` - Get user public key
- ✅ `rn_keys_node_get_public_key()` - Get node public key
- ✅ `rn_keys_node_get_agreement_public_key()` - Get node agreement public key
- ✅ `rn_keys_node_get_node_id()` - Get node ID
- ✅ `rn_keys_node_generate_csr()` - Generate CSR
- ✅ `rn_keys_mobile_process_setup_token()` - Process setup token
- ✅ `rn_keys_node_install_certificate()` - Install certificate

### **Network Key Functions:**
- ✅ `rn_keys_mobile_generate_network_data_key()` - Generate network data key
- ✅ `rn_keys_mobile_get_network_public_key()` - Get network public key
- ✅ `rn_keys_mobile_create_network_key_message()` - Create network key message
- ✅ `rn_keys_node_install_network_key()` - Install network key

### **Profile Key Functions:**
- ✅ `rn_keys_mobile_derive_user_profile_key()` - Derive user profile key

### **Encryption Functions:**
- ✅ `rn_keys_node_encrypt_with_envelope()` - Node envelope encryption
- ✅ `rn_keys_mobile_encrypt_with_envelope()` - Mobile envelope encryption
- ✅ `rn_keys_decrypt_envelope()` - Decrypt envelope
- ✅ `rn_keys_encrypt_local_data()` - Encrypt local data
- ✅ `rn_keys_decrypt_local_data()` - Decrypt local data

### **Message Encryption Functions:**
- ✅ `rn_keys_encrypt_message_for_mobile()` - Encrypt message for mobile
- ✅ `rn_keys_encrypt_message_for_node()` - Encrypt message for node
- ✅ `rn_keys_mobile_decrypt_message_from_node()` - Decrypt message from node
- ✅ `rn_keys_decrypt_message_from_mobile()` - Decrypt message from mobile

### **Persistence & State Functions:**
- ✅ `rn_keys_set_persistence_dir()` - Set persistence directory
- ✅ `rn_keys_enable_auto_persist()` - Enable auto-persist
- ✅ `rn_keys_wipe_persistence()` - Wipe persistence
- ✅ `rn_keys_flush_state()` - Flush state
- ✅ `rn_keys_node_get_keystore_state()` - Get node keystore state
- ✅ `rn_keys_mobile_get_keystore_state()` - Get mobile keystore state
- ✅ `rn_keys_get_keystore_caps()` - Get keystore capabilities

### **Device Keystore Functions:**
- ✅ `rn_keys_register_apple_device_keystore()` - Register Apple device keystore
- ✅ `rn_keys_register_linux_device_keystore()` - Register Linux device keystore

### **Additional Functions:**
- ✅ `rn_keys_set_label_mapping()` - Set label mapping
- ✅ `rn_keys_set_local_node_info()` - Set local node info
- ✅ `rn_keys_encrypt_for_public_key()` - Encrypt for public key
- ✅ `rn_keys_encrypt_for_network()` - Encrypt for network
- ✅ `rn_keys_decrypt_network_data()` - Decrypt network data
- ✅ `rn_keys_ensure_symmetric_key()` - Ensure symmetric key

## **📋 CORE DESIGN DECISIONS**

NO BACKWARDS compatibnility.. replace all .. this is a new codebase

### **1. Mirror Rust Architecture**
The Swift implementation must directly mirror the Rust FFI design:

```swift
/// Swift equivalent of KeysInner structure
public class KeysFFI {
    private let logger: Logger
    private var mobileKeyManager: MobileKeyManager?
    private var nodeKeyManager: NodeKeyManager?

    // Supporting fields mirroring Rust
    private var labelResolver: LabelResolver?
    private var localNodeInfo: Atomic<NodeInfo?>
    private var deviceKeystore: DeviceKeystore?
    private var persistenceDir: URL?
    private var autoPersist: Bool
}
```

### **2. Explicit Initialization Pattern**
Following the Rust pattern with clear, separate initialization:

```swift
// Initialize as mobile manager
public func keysInitAsMobile() throws

// Initialize as node manager
public func keysInitAsNode() throws
```

### **3. Function-Specific Validation**
Each function validates upfront with early returns on errors:

**Mobile Functions:**
```swift
func mobileEncryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
    // Validate upfront - exit early on errors
    guard let mobileManager = validateMobileManager() else {
        throw FFIError.wrongManagerType("Expected mobile manager, found node manager")
    }

    // Main logic - manager is guaranteed to exist
    return try mobileManager.encryptWithEnvelope(data: data, networkId: networkId, profileKeys: profileKeys)
}
```

**Node Functions:**
```swift
func nodeEncryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
    // Validate upfront - exit early on errors
    guard let nodeManager = validateNodeManager() else {
        throw FFIError.wrongManagerType("Expected node manager, found mobile manager")
    }

    // Main logic - manager is guaranteed to exist
    return try nodeManager.encryptWithEnvelope(data: data, networkId: networkId, profileKeys: profileKeys)
}
```

### **4. No Decision Logic, No Fallbacks**
- **Mobile functions** use only `mobileKeyManager`
- **Node functions** use only `nodeKeyManager`
- **Error if wrong type** is initialized
- **Error if not initialized** at all

---

## **🔧 IMPLEMENTATION PHASES**

### **PHASE 1: Critical Missing Functions (Week 1-2)**

#### **1.1 Core Initialization Functions**
**File:** `Sources/RunarFFI/KeysFFI.swift`

```swift
// Add these critical missing functions to KeysFFI class
public func keysInitAsMobile() throws {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    let (_, err) = withRnError { errPtr in
        rn_keys_init_as_mobile(h, errPtr)
    }
    if let e = err { throw e }
    
    // Update internal state
    let manager = MobileKeyManagerImpl(handle: h, logger: logger)
    mobileKeyManager = manager
    nodeKeyManager = nil
    
    logger.info("Initialized as mobile key manager")
}

public func keysInitAsNode() throws {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    let (_, err) = withRnError { errPtr in
        rn_keys_init_as_node(h, errPtr)
    }
    if let e = err { throw e }
    
    // Update internal state
    let manager = NodeKeyManagerImpl(handle: h, logger: logger)
    nodeKeyManager = manager
    mobileKeyManager = nil
    
    logger.info("Initialized as node key manager")
}
```

#### **1.2 Message Encryption Functions**
**File:** `Sources/RunarFFI/KeysFFI.swift`

```swift
// Add these critical missing message encryption functions
public func encryptMessageForMobile(message: Data, mobilePublicKey: Data) throws -> Data {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    var out: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (_, err) = withRnError { errPtr in
        message.withUnsafeBytes { msgRaw in
            mobilePublicKey.withUnsafeBytes { pkRaw in
                rn_keys_encrypt_message_for_mobile(
                    h,
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
    if let e = err { throw e }
    
    guard let p = out else { return Data() }
    let data = Data(bytes: p, count: outLen)
    rn_free(p, outLen)
    return data
}

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

public func mobileDecryptMessageFromNode(encryptedMessage: Data) throws -> Data {
    let manager = try validateMobileManager()
    return try manager.decryptMessageFromNode(encryptedMessage)
}

public func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data {
    let manager = try validateNodeManager()
    return try manager.decryptMessageFromMobile(encryptedMessage)
}
```

#### **1.3 Envelope Decryption Functions**
**File:** `Sources/RunarFFI/KeysFFI.swift`

```swift
// Add these critical missing envelope decryption functions
public func nodeDecryptEnvelope(eedCbor: Data) throws -> Data {
    let manager = try validateNodeManager()
    return try manager.decryptEnvelope(eedCbor)
}

public func mobileDecryptEnvelope(eedCbor: Data) throws -> Data {
    let manager = try validateMobileManager()
    return try manager.decryptEnvelope(eedCbor)
}
```

#### **1.4 Additional Missing Functions**
**File:** `Sources/RunarFFI/KeysFFI.swift`

```swift
// Add these additional missing functions
public func mobileInstallNetworkPublicKey(networkPublicKey: Data) throws {
    let manager = try validateMobileManager()
    try manager.installNetworkPublicKey(networkPublicKey)
}

public func encryptForPublicKey(data: Data, recipientPublicKey: Data) throws -> Data {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    var out: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (_, err) = withRnError { errPtr in
        data.withUnsafeBytes { dataRaw in
            recipientPublicKey.withUnsafeBytes { pkRaw in
                rn_keys_encrypt_for_public_key(
                    h,
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
    if let e = err { throw e }
    
    guard let p = out else { return Data() }
    let data = Data(bytes: p, count: outLen)
    rn_free(p, outLen)
    return data
}

public func encryptForNetwork(data: Data, networkId: String) throws -> Data {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    var out: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (_, err) = withRnError { errPtr in
        data.withUnsafeBytes { dataRaw in
            networkId.withCString { cNid in
                rn_keys_encrypt_for_network(
                    h,
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
    if let e = err { throw e }
    
    guard let p = out else { return Data() }
    let data = Data(bytes: p, count: outLen)
    rn_free(p, outLen)
    return data
}

public func decryptNetworkData(eedCbor: Data) throws -> Data {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    var out: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (_, err) = withRnError { errPtr in
        eedCbor.withUnsafeBytes { cborRaw in
            rn_keys_decrypt_network_data(
                h,
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

public func ensureSymmetricKey(keyName: String) throws -> Data {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    var out: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (_, err) = withRnError { errPtr in
        keyName.withCString { cName in
            rn_keys_ensure_symmetric_key(
                h,
                cName,
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

public func nodeGetNodeId() throws -> String {
    let manager = try validateNodeManager()
    return try manager.getNodeId()
}

public func flushState() throws {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    let (_, err) = withRnError { errPtr in
        rn_keys_flush_state(h, errPtr)
    }
    if let e = err { throw e }
}

public func getKeystoreCaps() throws -> RNAPIRnDeviceKeystoreCaps {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    var caps = RNAPIRnDeviceKeystoreCaps(version: 0, flags: 0)
    let (_, err) = withRnError { errPtr in
        rn_keys_get_keystore_caps(h, &caps, errPtr)
    }
    if let e = err { throw e }
    
    return caps
}

public func wipePersistence() throws {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    let (_, err) = withRnError { errPtr in
        rn_keys_wipe_persistence(h, errPtr)
    }
    if let e = err { throw e }
}
```

#### **1.5 Update Manager Protocols**
**File:** `Sources/RunarFFI/KeysFFI.swift`

```swift
// Update MobileKeyManager protocol to include missing functions
public protocol MobileKeyManager {
    // ... existing functions ...
    
    // Add these missing functions
    func decryptMessageFromNode(encryptedMessage: Data) throws -> Data
    func decryptEnvelope(eedCbor: Data) throws -> Data
    func installNetworkPublicKey(networkPublicKey: Data) throws
    
    // REMOVE these non-existent functions:
    // func generateCSR() throws -> Data  // ❌ DOES NOT EXIST IN RUST FFI
    // func installCertificate(_ nodeCertificateMessageCBOR: Data) throws  // ❌ DOES NOT EXIST IN RUST FFI
}

// Update NodeKeyManager protocol to include missing functions
public protocol NodeKeyManager {
    // ... existing functions ...
    
    // Add these missing functions
    func decryptMessageFromMobile(encryptedMessage: Data) throws -> Data
    func decryptEnvelope(eedCbor: Data) throws -> Data
    func getNodeId() throws -> String
}
```

#### **1.6 Clean Up Deprecated Functions**
**File:** `Sources/RunarFFI/KeysFFI.swift`

```swift
// REMOVE these public functions from KeysFFI class:
// public func mobileGenerateCSR() throws -> Data  // ❌ DOES NOT EXIST IN RUST FFI
// public func mobileInstallCertificate(_ nodeCertificateMessageCBOR: Data) throws  // ❌ DOES NOT EXIST IN RUST FFI

// REMOVE these functions from MobileKeyManagerImpl:
// func generateCSR() throws -> Data  // ❌ DOES NOT EXIST IN RUST FFI
// func installCertificate(_ nodeCertificateMessageCBOR: Data) throws  // ❌ DOES NOT EXIST IN RUST FFI
```

#### **1.7 Implement Apple-Specific Functions**
**File:** `Sources/RunarFFI/KeysFFI.swift`

```swift
// Add these Apple-specific functions to KeysFFI class
public func registerAppleDeviceKeystore(label: String) throws {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    let (_, err) = withRnError { errPtr in
        label.withCString { cLabel in
            rn_keys_register_apple_device_keystore(h, cLabel, errPtr)
        }
    }
    if let e = err { throw e }
    
    logger.info("Apple device keystore registered with label: \(label)")
}

public func registerLinuxDeviceKeystore(service: String, account: String) throws {
    guard let h = handle else {
        throw FFIError.invalidHandle("Keys handle not initialized")
    }
    
    let (_, err) = withRnError { errPtr in
        service.withCString { cService in
            account.withCString { cAccount in
                rn_keys_register_linux_device_keystore(h, cService, cAccount, errPtr)
            }
        }
    }
    if let e = err { throw e }
    
    logger.info("Linux device keystore registered with service: \(service), account: \(account)")
}

// Update the existing placeholder implementations
public func mobileRegisterDeviceKeystore(_ keystore: DeviceKeystore) throws {
    // This is now handled by the platform-specific registration functions above
    // The DeviceKeystore protocol is kept for compatibility but actual registration
    // goes through the FFI functions
    logger.info("Device keystore registration handled by platform-specific functions")
}

public func nodeRegisterDeviceKeystore(_ keystore: DeviceKeystore) throws {
    // This is now handled by the platform-specific registration functions above
    // The DeviceKeystore protocol is kept for compatibility but actual registration
    // goes through the FFI functions
    logger.info("Device keystore registration handled by platform-specific functions")
}
```

#### **1.6 Create Validation Helpers**
**File:** `Sources/RunarFFI/KeysFFI+Validation.swift`

```swift
extension KeysFFI {
    /// Validate mobile key manager exists and node manager doesn't
    /// - Returns: MobileKeyManager if validation passes
    /// - Throws: FFIError if validation fails
    func validateMobileManager() throws -> MobileKeyManager {
        // Check for wrong manager type first
        if nodeKeyManager != nil {
            throw FFIError.wrongManagerType("Expected mobile manager, found node manager")
        }

        // Check if mobile manager exists
        guard let manager = mobileKeyManager else {
            throw FFIError.notInitialized
        }

        return manager
    }

    /// Validate node key manager exists and mobile manager doesn't
    /// - Returns: NodeKeyManager if validation passes
    /// - Throws: FFIError if validation fails
    func validateNodeManager() throws -> NodeKeyManager {
        // Check for wrong manager type first
        if mobileKeyManager != nil {
            throw FFIError.wrongManagerType("Expected node manager, found mobile manager")
        }

        // Check if node manager exists
        guard let manager = nodeKeyManager else {
            throw FFIError.notInitialized
        }

        return manager
    }
}
```

#### **1.3 Create Initialization Functions**
**File:** `Sources/RunarFFI/KeysFFI+Initialization.swift`

```swift
extension KeysFFI {
    /// Initialize FFI instance as mobile manager
    /// - Throws: FFIError if already initialized with different type
    public func initializeAsMobile() throws {
        // Check if already initialized with wrong type
        if nodeKeyManager != nil {
            throw FFIError.wrongManagerType("Already initialized as node manager")
        }

        // Check if already initialized as mobile
        if mobileKeyManager != nil {
            return // Already initialized correctly
        }

        // Initialize mobile manager
        let manager = try MobileKeyManager(logger: logger)

        // Apply existing configuration
        if let keystore = deviceKeystore {
            manager.registerDeviceKeystore(keystore)
        }
        if let dir = persistenceDir {
            manager.setPersistenceDirectory(dir)
        }
        manager.enableAutoPersist(autoPersist)

        mobileKeyManager = manager
    }

    /// Initialize FFI instance as node manager
    /// - Throws: FFIError if already initialized with different type
    public func initializeAsNode() throws {
        // Check if already initialized with wrong type
        if mobileKeyManager != nil {
            throw FFIError.wrongManagerType("Already initialized as mobile manager")
        }

        // Check if already initialized as node
        if nodeKeyManager != nil {
            return // Already initialized correctly
        }

        // Initialize node manager
        let manager = try NodeKeyManager(logger: logger)

        // Apply existing configuration
        if let keystore = deviceKeystore {
            manager.registerDeviceKeystore(keystore)
        }
        if let dir = persistenceDir {
            manager.setPersistenceDirectory(dir)
        }
        manager.enableAutoPersist(autoPersist)

        nodeKeyManager = manager
    }
}
```

---

### **PHASE 2: Standardize Error Handling**

#### **2.1 Define Error Types**
**File:** `Sources/RunarFFI/FFIErrors.swift`

```swift
import Foundation

/// Swift FFI Error types - mirroring Rust error codes
public enum FFIError: LocalizedError {
    case nullArgument(String)
    case invalidHandle(String)
    case notInitialized
    case wrongManagerType(String)
    case operationFailed(String)
    case serializationFailed(String)
    case keystoreFailed(String)
    case memoryAllocation(String)
    case lockError(String)
    case invalidUTF8(String)

    public var errorDescription: String? {
        switch self {
        case .nullArgument(let msg):
            return "Null argument: \(msg)"
        case .invalidHandle(let msg):
            return "Invalid handle: \(msg)"
        case .notInitialized:
            return "FFI instance not initialized"
        case .wrongManagerType(let msg):
            return "Wrong manager type: \(msg)"
        case .operationFailed(let msg):
            return "Operation failed: \(msg)"
        case .serializationFailed(let msg):
            return "Serialization failed: \(msg)"
        case .keystoreFailed(let msg):
            return "Keystore operation failed: \(msg)"
        case .memoryAllocation(let msg):
            return "Memory allocation failed: \(msg)"
        case .lockError(let msg):
            return "Lock acquisition failed: \(msg)"
        case .invalidUTF8(let msg):
            return "Invalid UTF-8 string: \(msg)"
        }
    }

    /// Error code constants - matching Rust error codes
    public var errorCode: Int32 {
        switch self {
        case .nullArgument: return 1
        case .invalidHandle: return 2
        case .notInitialized: return 3
        case .wrongManagerType: return 4
        case .operationFailed: return 5
        case .serializationFailed: return 6
        case .keystoreFailed: return 7
        case .memoryAllocation: return 8
        case .lockError: return 9
        case .invalidUTF8: return 10
        }
    }
}
```

---

### **PHASE 3: Function-Specific Updates**

#### **3.1 Split Decision-Logic Functions**

**Replace:** `keysEncryptWithEnvelope()` function
**With:**
```swift
/// Node-specific envelope encryption
/// - Parameters:
///   - data: Data to encrypt
///   - networkId: Optional network identifier
///   - profileKeys: Optional profile public keys for additional recipients
/// - Returns: CBOR-encoded EncryptedEnvelopeData
/// - Throws: FFIError if operation fails
public func nodeEncryptWithEnvelope(
    data: Data,
    networkId: String? = nil,
    profileKeys: [Data]? = nil
) throws -> Data {
    // Validate parameters upfront - specific error messages
    guard !data.isEmpty else {
        throw FFIError.nullArgument("Data cannot be empty")
    }

    // Additional validation for profile keys if provided
    if let keys = profileKeys, !keys.isEmpty {
        for (index, key) in keys.enumerated() {
            guard !key.isEmpty else {
                throw FFIError.nullArgument("Profile key at index \(index) is empty")
            }
        }
    }

    // Validate manager upfront - exit early on errors
    let manager = try validateNodeManager()

    // Main logic - manager is guaranteed to exist
    return try manager.encryptWithEnvelope(
        data: data,
        networkId: networkId,
        profileKeys: profileKeys
    )
}

/// Mobile-specific envelope encryption
/// - Parameters:
///   - data: Data to encrypt
///   - networkId: Optional network identifier
///   - profileKeys: Optional profile public keys for additional recipients
/// - Returns: CBOR-encoded EncryptedEnvelopeData
/// - Throws: FFIError if operation fails
public func mobileEncryptWithEnvelope(
    data: Data,
    networkId: String? = nil,
    profileKeys: [Data]? = nil
) throws -> Data {
    // Validate parameters upfront - specific error messages
    guard !data.isEmpty else {
        throw FFIError.nullArgument("Data cannot be empty")
    }

    // Additional validation for profile keys if provided
    if let keys = profileKeys, !keys.isEmpty {
        for (index, key) in keys.enumerated() {
            guard !key.isEmpty else {
                throw FFIError.nullArgument("Profile key at index \(index) is empty")
            }
        }
    }

    // Validate manager upfront - exit early on errors
    let manager = try validateMobileManager()

    // Main logic - manager is guaranteed to exist
    return try manager.encryptWithEnvelope(
        data: data,
        networkId: networkId,
        profileKeys: profileKeys
    )
}
```

#### **3.2 Update Node-Only Functions**
Functions like `encryptLocalData()` become node-specific:

```swift
/// Node-specific local data encryption
/// - Parameter data: Data to encrypt
/// - Returns: Encrypted data
/// - Throws: FFIError if operation fails
public func nodeEncryptLocalData(data: Data) throws -> Data {
    // Validate parameters upfront
    guard !data.isEmpty else {
        throw FFIError.nullArgument("Data cannot be empty")
    }

    // Validate manager upfront
    let manager = try validateNodeManager()

    // Main logic - manager is guaranteed to exist
    return try manager.encryptLocalData(data)
}
```

#### **3.3 Update Mobile-Only Functions**
Remove duplicated initialization code and use upfront validation:

```swift
/// Mobile-specific user root key initialization
/// - Throws: FFIError if operation fails
public func mobileInitializeUserRootKey() throws {
    // Validate manager upfront
    let manager = try validateMobileManager()

    // Main logic - manager is guaranteed to exist
    try manager.initializeUserRootKey()
}
```

---

### **PHASE 4: Update Supporting Functions**

#### **4.1 Update Persistence Functions**
```swift
/// Set persistence directory for key managers
/// - Parameter directory: Directory URL for persistence
/// - Throws: FFIError if operation fails
public func setPersistenceDirectory(_ directory: URL) throws {
    // Validate directory
    guard directory.isFileURL else {
        throw FFIError.nullArgument("Directory must be a file URL")
    }

    // Set directory for whichever manager exists
    if let manager = nodeKeyManager {
        try manager.setPersistenceDirectory(directory)
    }
    if let manager = mobileKeyManager {
        try manager.setPersistenceDirectory(directory)
    }

    persistenceDir = directory
}
```

#### **4.2 Update Device Keystore Registration**
```swift
/// Register Apple device keystore
/// - Parameter label: Keychain label for the keystore
/// - Throws: FFIError if operation fails
public func registerAppleDeviceKeystore(label: String) throws {
    // Create Apple-specific keystore
    let keystore = try AppleDeviceKeystore(label: label)

    // Register with whichever manager exists
    if let manager = nodeKeyManager {
        try manager.registerDeviceKeystore(keystore)
    }
    if let manager = mobileKeyManager {
        try manager.registerDeviceKeystore(keystore)
    }

    deviceKeystore = keystore
}
```

---

## **🔍 IMPROVED VALIDATION PATTERNS**

### **Parameter Validation Examples**

#### **1. Functions with Complex Parameters**
```swift
func nodeEncryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
    // Validate each parameter specifically with descriptive error messages
    guard !data.isEmpty else {
        throw FFIError.nullArgument("Data buffer is empty")
    }

    if let networkId = networkId {
        guard !networkId.isEmpty else {
            throw FFIError.nullArgument("Network ID cannot be empty string")
        }
        guard networkId.utf8.count <= 255 else {
            throw FFIError.nullArgument("Network ID too long (max 255 bytes)")
        }
    }

    // Additional validation for profile keys
    if let keys = profileKeys {
        guard keys.count <= 1000 else {
            throw FFIError.nullArgument("Too many profile keys (max 1000)")
        }
        for (index, key) in keys.enumerated() {
            guard key.count >= 32 else {
                throw FFIError.nullArgument("Profile key at index \(index) too short (min 32 bytes)")
            }
            guard key.count <= 1024 else {
                throw FFIError.nullArgument("Profile key at index \(index) too long (max 1024 bytes)")
            }
        }
    }
    // ... rest of function
}
```

#### **2. Functions with String Parameters**
```swift
func setLabel(_ label: String) throws {
    // Validate string parameters
    guard !label.isEmpty else {
        throw FFIError.nullArgument("Label cannot be empty")
    }
    guard label.utf8.count <= 255 else {
        throw FFIError.nullArgument("Label too long (max 255 bytes)")
    }
    guard label.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil else {
        throw FFIError.nullArgument("Label contains invalid characters")
    }
    // ... rest of function
}
```

#### **3. Functions with Optional Parameters**
```swift
func configureNetwork(networkId: String?, timeout: TimeInterval?) throws {
    // Check optional parameters only if they should be provided
    if let networkId = networkId {
        guard !networkId.isEmpty else {
            throw FFIError.nullArgument("Network ID required when provided")
        }
    }

    if let timeout = timeout {
        guard timeout > 0 else {
            throw FFIError.nullArgument("Timeout must be positive")
        }
        guard timeout <= 300 else {
            throw FFIError.nullArgument("Timeout too long (max 300 seconds)")
        }
    }
    // ... rest of function
}
```

---

## **📋 IMPLEMENTATION CHECKLIST**

### **Phase 1: Critical Missing Functions (Week 1-2)**
- [ ] **IMPLEMENT CRITICAL MISSING FUNCTIONS:**
  - [ ] `keysInitAsMobile()` - **CRITICAL MISSING**
  - [ ] `keysInitAsNode()` - **CRITICAL MISSING**
  - [ ] `encryptMessageForMobile()` - **CRITICAL MISSING**
  - [ ] `encryptMessageForNode()` - **CRITICAL MISSING**
  - [ ] `mobileDecryptMessageFromNode()` - **CRITICAL MISSING**
  - [ ] `decryptMessageFromMobile()` - **CRITICAL MISSING**
  - [ ] `nodeDecryptEnvelope()` - **CRITICAL MISSING**
  - [ ] `mobileDecryptEnvelope()` - **CRITICAL MISSING**

### **Phase 2: Additional Missing Functions (Week 3)**
- [ ] **IMPLEMENT ADDITIONAL MISSING FUNCTIONS:**
  - [ ] `mobileInstallNetworkPublicKey()` - **CRITICAL MISSING**
  - [ ] `encryptForPublicKey()` - **CRITICAL MISSING**
  - [ ] `encryptForNetwork()` - **CRITICAL MISSING**
  - [ ] `decryptNetworkData()` - **CRITICAL MISSING**
  - [ ] `ensureSymmetricKey()` - **CRITICAL MISSING**
  - [ ] `nodeGetNodeId()` - **CRITICAL MISSING**
  - [ ] `flushState()` - **CRITICAL MISSING**
  - [ ] `getKeystoreCaps()` - **CRITICAL MISSING**
  - [ ] `wipePersistence()` - **CRITICAL MISSING**

### **Phase 3: Update Manager Protocols (Week 4)**
- [ ] **UPDATE MANAGER PROTOCOLS:**
  - [ ] Add missing functions to `MobileKeyManager` protocol
  - [ ] Add missing functions to `NodeKeyManager` protocol
  - [ ] Update manager implementations with new functions
  - [ ] Implement device keystore registration functions

### **Phase 4: Clean Up Deprecated Functions (Week 5)**
- [ ] **REMOVE NON-EXISTENT FUNCTIONS:**
  - [ ] `mobileGenerateCSR()` - **DOES NOT EXIST IN RUST FFI** - Must be removed
  - [ ] `mobileInstallCertificate()` - **DOES NOT EXIST IN RUST FFI** - Must be removed
  - [ ] Remove from `MobileKeyManager` protocol
  - [ ] Remove from `MobileKeyManagerImpl` implementation
  - [ ] Remove from `KeysFFI` public API

- [ ] **IMPLEMENT APPLE-SPECIFIC FUNCTIONS:**
  - [ ] `registerAppleDeviceKeystore()` - **MUST IMPLEMENT** Apple Keychain integration
  - [ ] `registerLinuxDeviceKeystore()` - **MUST IMPLEMENT** Linux keyring integration
  - [ ] `getKeystoreCaps()` - **MUST IMPLEMENT** device keystore capabilities
  - [ ] `wipePersistence()` - **MUST IMPLEMENT** secure data cleanup
  - [ ] `flushState()` - **MUST IMPLEMENT** state persistence

- [ ] **UPDATE EXISTING PLACEHOLDERS:**
  - [ ] Update `mobileRegisterDeviceKeystore()` to use platform-specific functions
  - [ ] Update `nodeRegisterDeviceKeystore()` to use platform-specific functions

### **Phase 5: Complete Lifecycle Test Implementation (Week 6-7)**
- [ ] **IMPLEMENT COMPLETE LIFECYCLE TEST:**
  - [ ] Replicate `ffi_lifecycle_test.rs` in Swift
  - [ ] Test complete mobile ↔ node setup workflow
  - [ ] Test certificate issuance and installation
  - [ ] Test network setup and key distribution
  - [ ] Test multi-recipient envelope encryption
  - [ ] Test cross-device data sharing
  - [ ] Test node local storage encryption
  - [ ] Test state persistence across operations

### **Phase 6: Integration & Validation (Week 8-9)**
- [ ] **VALIDATE WITH RUST IMPLEMENTATION:**
  - [ ] Run Swift and Rust tests in parallel
  - [ ] Verify identical cryptographic results
  - [ ] Performance comparison and optimization
  - [ ] Memory safety validation
  - [ ] Error handling validation

### **Phase 7: Documentation & Finalization (Week 10-11)**
- [ ] **FINAL DOCUMENTATION:**
  - [ ] Update API documentation with all functions
  - [ ] Document error codes and their meanings
  - [ ] Create comprehensive examples
  - [ ] Final code review and optimization
  - [ ] Performance testing and validation

---

## **🎯 SUCCESS CRITERIA**

### **Code Quality:**
- ✅ **Zero decision logic** - no complex if/else chains for manager selection
- ✅ **Zero code duplication** - single initialization path per manager type
- ✅ **Single responsibility** - each function does exactly one thing
- ✅ **Consistent error handling** - all functions use FFIError types

### **Architecture:**
- ✅ **Separate manager fields** - clear separation between mobile and node
- ✅ **Explicit initialization** - clear functions for each manager type
- ✅ **No lazy initialization** - functions validate and throw errors
- ✅ **No fallbacks** - clear errors for wrong manager types

### **API Design:**
- ✅ **Clear function names** - `node*()` and `mobile*()` prefixes
- ✅ **Predictable behavior** - each function's purpose is obvious
- ✅ **Proper error handling** - all error cases throw appropriate FFIError

### **Apple Platform Best Practices:**
- ✅ **Swift concurrency** - proper async/await patterns
- ✅ **Memory management** - ARC-optimized data handling
- ✅ **Security** - CryptoKit integration for encryption
- ✅ **Error handling** - Swift's Result types and throwing functions

### **Comprehensive Testing:**
- ✅ **100% API Coverage** - All 40+ Rust FFI functions implemented
- ✅ **Complete Lifecycle Test** - Full replication of `ffi_lifecycle_test.rs`
- ✅ **Identical Cryptographic Results** - Same keys, certificates, and encrypted data
- ✅ **Cross-Language Validation** - Swift and Rust produce identical results
- ✅ **Memory Safety** - No leaks or corruption in Swift implementation
- ✅ **Performance Parity** - Swift performance matches Rust performance

### **Critical Gap Resolution:**
- ✅ **All 17 Missing Functions Implemented** - Complete API coverage
- ✅ **All Placeholder Functions Fixed** - Real implementations replace placeholders
- ✅ **Manager Protocols Updated** - All missing functions added to protocols
- ✅ **Complete Lifecycle Test** - Full end-to-end workflow validation

---

## **🚀 IMMEDIATE NEXT STEPS**

### **CRITICAL PRIORITY: Implement Missing Functions**

1. **Phase 1 (Week 1-2):** Implement the 8 most critical missing functions:
   - `keysInitAsMobile()` and `keysInitAsNode()` - **CRITICAL FOR INITIALIZATION**
   - Message encryption/decryption functions - **CRITICAL FOR COMMUNICATION**
   - Envelope decryption functions - **CRITICAL FOR DATA ACCESS**

2. **Phase 2 (Week 3):** Implement the 9 additional missing functions:
   - Network and profile key functions
   - Additional encryption functions
   - Utility and state management functions

3. **Phase 3 (Week 4):** Update manager protocols and implementations

4. **Phase 4 (Week 5):** Fix placeholder functions with real implementations

5. **Phase 5 (Week 6-7):** Implement complete lifecycle test

### **IMPACT OF MISSING FUNCTIONS**

The current Swift FFI implementation is **missing 17 critical functions** that are essential for:
- **Mobile ↔ Node Communication** - Setup tokens, certificates, messages
- **Data Encryption/Decryption** - Envelopes, network data, local storage
- **Key Management** - Network keys, profile keys, symmetric keys
- **State Management** - Persistence, keystore capabilities, state flushing

Without these functions, the Swift FFI cannot replicate the complete Rust FFI workflow and will fail the comprehensive lifecycle test.

### **IMPACT OF DEPRECATED FUNCTIONS**

The current Swift FFI implementation **contains 2 functions that never existed** in the Rust FFI API:
- **`mobileGenerateCSR()`** - This function was never part of the Rust FFI
- **`mobileInstallCertificate()`** - This function was never part of the Rust FFI

These functions create:
- **False expectations** about available functionality
- **Testing failures** since they cannot be validated against Rust
- **API misalignment** between Swift and Rust implementations
- **Technical debt** that must be cleaned up

**These functions must be completely removed** to achieve 100% alignment with the Rust FFI API.

### **CLEANUP REQUIREMENTS**

#### **Functions to Remove from Swift FFI:**
1. **`mobileGenerateCSR()`** - Remove from:
   - `MobileKeyManager` protocol
   - `MobileKeyManagerImpl` implementation
   - `KeysFFI` public API

2. **`mobileInstallCertificate()`** - Remove from:
   - `MobileKeyManager` protocol
   - `MobileKeyManagerImpl` implementation
   - `KeysFFI` public API

#### **Why These Functions Don't Exist:**
- **Mobile devices don't generate CSRs** - Only nodes generate CSRs for certificate requests
- **Mobile devices don't install certificates** - Only nodes install certificates from mobile CA
- **These functions were incorrectly implemented** based on assumptions, not the actual Rust FFI API

#### **Correct Workflow:**
- **Mobile**: Generates user root key, processes setup tokens, issues certificates
- **Node**: Generates CSR, receives and installs certificates from mobile
- **No overlap** - Each side has distinct responsibilities

### **APPLE-SPECIFIC IMPLEMENTATION REQUIREMENTS**

#### **Critical Apple Functions (MUST IMPLEMENT):**
The Swift FFI implementation **MUST** implement these Apple-specific functions as they are essential for iOS/macOS integration:

1. **`registerAppleDeviceKeystore(label: String)`** - **CRITICAL FOR APPLE PLATFORMS**
   - Integrates with Apple Keychain and Secure Enclave
   - Provides hardware-backed key storage
   - Essential for production iOS/macOS apps

2. **`getKeystoreCaps()`** - **CRITICAL FOR CAPABILITY DETECTION**
   - Returns device keystore capabilities
   - Indicates Secure Enclave availability
   - Shows authentication requirements

3. **`wipePersistence()`** - **CRITICAL FOR SECURITY**
   - Securely removes all persisted data
   - Essential for app uninstall and data cleanup
   - Must use secure deletion methods

4. **`flushState()`** - **CRITICAL FOR DATA INTEGRITY**
   - Ensures all state changes are persisted
   - Critical for crash recovery
   - Must use atomic write operations

#### **Apple Platform Integration:**
- **iOS**: Must use Keychain Services and Secure Enclave when available
- **macOS**: Must use Keychain Services with appropriate access controls
- **Security**: Must implement proper entitlements and access control
- **Performance**: Must use efficient key derivation and storage

### **SUCCESS METRICS**

- ✅ **17 Missing Functions Implemented** - Complete API coverage
- ✅ **2 Deprecated Functions Removed** - Clean API alignment with Rust FFI
- ✅ **4 Apple-Specific Functions Implemented** - Full Apple platform integration
- ✅ **Complete Lifecycle Test Passing** - Identical results with Rust
- ✅ **100% Function Coverage** - All Rust FFI functions available in Swift
- ✅ **Production Ready** - No placeholders, no shortcuts, real implementations
- ✅ **Clean Codebase** - No deprecated or non-existent functions
- ✅ **Apple Platform Ready** - Keychain and Secure Enclave integration

---

## **🔄 Integration with Rust API**

### **Function Name Mapping**
The Swift functions will mirror the Rust FFI function names:

#### **Core Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_new()` | `keysNew()` |
| `rn_keys_init_as_mobile()` | `keysInitAsMobile()` |
| `rn_keys_init_as_node()` | `keysInitAsNode()` |
| `rn_keys_free()` | `keysFree()` |

#### **Key Management Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_mobile_initialize_user_root_key()` | `mobileInitializeUserRootKey()` |
| `rn_keys_mobile_get_user_public_key()` | `mobileGetUserPublicKey()` |
| `rn_keys_node_get_public_key()` | `nodeGetPublicKey()` |
| `rn_keys_node_get_agreement_public_key()` | `nodeGetAgreementPublicKey()` |
| `rn_keys_node_get_node_id()` | `nodeGetNodeId()` |

#### **Certificate/Setup Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_node_generate_csr()` | `nodeGenerateCsr()` |
| `rn_keys_mobile_process_setup_token()` | `mobileProcessSetupToken()` |
| `rn_keys_node_install_certificate()` | `nodeInstallCertificate()` |

#### **Network Key Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_mobile_generate_network_data_key()` | `mobileGenerateNetworkDataKey()` |
| `rn_keys_mobile_get_network_public_key()` | `mobileGetNetworkPublicKey()` |
| `rn_keys_mobile_create_network_key_message()` | `mobileCreateNetworkKeyMessage()` |
| `rn_keys_node_install_network_key()` | `nodeInstallNetworkKey()` |

#### **Profile Key Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_mobile_derive_user_profile_key()` | `mobileDeriveUserProfileKey()` |

#### **Encryption Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_node_encrypt_with_envelope()` | `nodeEncryptWithEnvelope()` |
| `rn_keys_mobile_encrypt_with_envelope()` | `mobileEncryptWithEnvelope()` |
| `rn_keys_decrypt_envelope()` | `decryptEnvelope()` |
| `rn_keys_encrypt_local_data()` | `encryptLocalData()` |
| `rn_keys_decrypt_local_data()` | `decryptLocalData()` |

#### **Message Encryption Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_encrypt_message_for_mobile()` | `encryptMessageForMobile()` |
| `rn_keys_encrypt_message_for_node()` | `encryptMessageForNode()` |
| `rn_keys_mobile_decrypt_message_from_node()` | `mobileDecryptMessageFromNode()` |
| `rn_keys_decrypt_message_from_mobile()` | `decryptMessageFromMobile()` |

#### **Persistence & State Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_set_persistence_dir()` | `setPersistenceDir()` |
| `rn_keys_enable_auto_persist()` | `enableAutoPersist()` |
| `rn_keys_wipe_persistence()` | `wipePersistence()` |
| `rn_keys_flush_state()` | `flushState()` |
| `rn_keys_node_get_keystore_state()` | `nodeGetKeystoreState()` |
| `rn_keys_mobile_get_keystore_state()` | `mobileGetKeystoreState()` |
| `rn_keys_get_keystore_caps()` | `getKeystoreCaps()` |

#### **Device Keystore Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_register_apple_device_keystore()` | `registerAppleDeviceKeystore()` |
| `rn_keys_register_linux_device_keystore()` | `registerLinuxDeviceKeystore()` |

#### **Additional Functions:**
| Rust Function | Swift Function |
|---------------|----------------|
| `rn_keys_set_label_mapping()` | `setLabelMapping()` |
| `rn_keys_set_local_node_info()` | `setLocalNodeInfo()` |
| `rn_keys_encrypt_for_public_key()` | `encryptForPublicKey()` |
| `rn_keys_encrypt_for_network()` | `encryptForNetwork()` |
| `rn_keys_decrypt_network_data()` | `decryptNetworkData()` |
| `rn_keys_ensure_symmetric_key()` | `ensureSymmetricKey()` |

### **Error Code Mapping**
Swift `FFIError` codes match Rust error codes exactly for seamless interop.

### **Memory Management**
- Swift uses ARC for automatic memory management
- CBOR data is handled as `Data` objects
- Pointer operations are encapsulated within the FFI layer

---

## **🧪 COMPREHENSIVE TEST REPLICATION REQUIREMENT**

### **Critical Requirement: Replicate `ffi_lifecycle_test.rs` in Swift**

The Swift FFI implementation **MUST** replicate the exact same end-to-end cryptographic flow as `ffi_lifecycle_test.rs`. This test validates the complete PKI + key management system and serves as the ultimate integration test.

### **Test Structure Requirements:**

#### **1. Complete End-to-End Flow**
```swift
func testCompleteSwiftFFILifecycle() {
    // ==========================================
    // Mobile side - first time use - generate user keys
    // ==========================================
    // 1 - (mobile side) - generate user master key
    // Generate user root agreement public key for ECIES
    // Get the user root public key (essential for encrypting setup tokens)

    // ==========================================
    // Node first time use - enter in setup mode
    // ==========================================
    // 2 - node side (setup mode) - generate its own TLS and Storage keypairs
    // and generate a setup handshake token which contains the CSR request and the node public key
    // Get the node public key (node ID) - keys are created in constructor
    // Generate setup token (CSR)
    // Encrypt setup token for mobile using user's public key

    // ==========================================
    // Mobile scans a Node QR code which contains the setup token
    // ==========================================
    // Mobile decodes the QR code and decrypts the setup token
    // Extract the node's public key from the now-decrypted setup token
    // 3 - (mobile side) - received the token and sign the CSR

    // ==========================================
    // Secure certificate transmission to node
    // ==========================================
    // The certificate message is serialized and then encrypted for the node using its public key
    // Node side - receives the encrypted certificate message, decrypts, and installs it
    // 4 - (node side) - received the certificate message, validates it, and stores it

    // ==========================================
    // Phase 3: Network Setup
    // ==========================================
    // 3.1 Mobile generates network data key
    // 3.2 Mobile creates network key message
    // 3.3 Node installs network key

    // ==========================================
    // Enhanced Key Management Testing
    // ==========================================
    // 7 - (mobile side) - User creates profile keys
    // Generate personal and work profile keys

    // ==========================================
    // Multi-Recipient Envelope Encryption
    // ==========================================
    // 8 - (mobile side) - Encrypts data using envelope which is encrypted using the
    // user profile key and network key, so only the user or apps running in the
    // network can decrypt it
    // 5.1 Mobile encrypts with envelope (with multiple profile keys)
    // 5.2 Node decrypts envelope

    // ==========================================
    // Node Local Storage Encryption
    // ==========================================
    // 10 - Test node local storage encryption
    // Encrypt and decrypt local file data

    // ==========================================
    // State Serialization and Restoration
    // ==========================================
    // Test that all state is properly maintained across operations
}
```

#### **2. Test Validation Requirements**
The Swift test **MUST** validate:

- ✅ **Mobile CA initialization** and user root key generation
- ✅ **Node setup token generation** and CSR workflow
- ✅ **Certificate issuance** and installation
- ✅ **Network setup** and key distribution
- ✅ **Enhanced key management** (profiles, networks, envelopes)
- ✅ **Multi-recipient envelope encryption**
- ✅ **Cross-device data sharing** (mobile ↔ node)
- ✅ **Node local storage encryption**
- ✅ **State persistence** across operations
- ✅ **Certificate installation verification**

#### **3. Test Architecture**
```swift
// Test file structure
final class SwiftFFILifecycleTests: XCTestCase {
    var mobileKeys: OpaquePointer!
    var nodeKeys: OpaquePointer!

    override func setUp() {
        super.setUp()
        // Initialize test fixtures
    }

    override func tearDown() {
        // Clean up resources
        super.tearDown()
    }

    func testCompleteSwiftFFILifecycle() {
        // Complete end-to-end test implementation
    }

    // Helper functions that mirror the Rust test
    func createKeysHandle() -> OpaquePointer { ... }
    func destroyKeysHandle(_ handle: OpaquePointer) { ... }
    func initAsMobile(_ handle: OpaquePointer) throws { ... }
    func initAsNode(_ handle: OpaquePointer) throws { ... }
}
```

#### **4. Integration Test Requirements**
- **Parallel Implementation**: Swift test should run in parallel with Rust test
- **Cross-Language Validation**: Both tests should produce identical cryptographic results
- **Performance Comparison**: Swift implementation should match Rust performance
- **Memory Safety**: Swift test should validate no memory leaks or corruption

#### **5. Success Criteria**
- ✅ **100% API Coverage**: All Rust FFI functions implemented in Swift
- ✅ **Identical Cryptographic Results**: Same keys, certificates, and encrypted data
- ✅ **Complete Workflow**: Full mobile ↔ node setup and communication flow
- ✅ **State Management**: Proper persistence and restoration
- ✅ **Error Handling**: All error paths tested and handled correctly

### **Implementation Priority**
1. **Phase 1**: Core FFI functions (initialization, key management)
2. **Phase 2**: Certificate/Setup workflow functions
3. **Phase 3**: Network and profile key functions
4. **Phase 4**: Encryption and message functions
5. **Phase 5**: Persistence and state management
6. **Phase 6**: Complete lifecycle test implementation

This design ensures the Swift FFI implementation perfectly aligns with the Rust architecture while following Apple's platform best practices and Swift idioms.

# Unified Key Store API Specification

## Overview

This specification defines a simplified unified key store API that provides common cryptographic operations for both mobile and node key stores, while maintaining direct access to mobile-specific and node-specific FFI operations when needed.

## Design Principles

1. **Common Operations Only**: The unified API only includes operations that both mobile and node key stores support
2. **Single Instance**: One key store instance per app/node, shared between common API and specific operations
3. **Direct FFI Access**: Mobile-specific operations (like `rn_keys_mobile_initialize_user_root_key`) accessed directly through FFI
4. **Minimal Abstraction**: Only abstract what's needed for serializer, node packages, and other consumers
5. **Platform Defaults**: iOS automatically uses mobile key store, macOS uses node key store

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Swift App/Node                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │   Serializer    │  │   Node Package  │  │   Tests     │ │
│  │  (Common API)   │  │  (Common API)   │  │ (Can Override)│ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    Unified Key Store                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              UnifiedKeyStore                        │   │
│  │  • encryptWithEnvelope()                           │   │
│  │  • decryptEnvelope()                               │   │
│  │  • encryptMessage()                                │   │
│  │  • decryptMessage()                                │   │
│  │  • encryptForNetwork()                             │   │
│  │  • decryptNetworkData()                            │   │
│  └─────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Key Store Manager                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           UnifiedKeyStoreManager                    │   │
│  │  • Single instance per app/node                     │   │
│  │  • Platform-appropriate defaults                    │   │
│  │  • Direct access to underlying FFI                  │   │
│  └─────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Swift FFI Layer                        │
│  ┌─────────────────┐  ┌─────────────────┐                │
│  │  MobileKeyStore │  │  NodeKeyStore   │                │
│  │  (Mobile FFI)   │  │  (Node FFI)     │                │
│  └─────────────────┘  └─────────────────┘                │
├─────────────────────────────────────────────────────────────┤
│                    Rust FFI                               │
│  ┌─────────────────┐  ┌─────────────────┐                │
│  │ rn_keys_mobile_*│  │ rn_keys_node_*  │                │
│  │ rn_keys_*       │  │ rn_keys_*       │                │
│  └─────────────────┘  └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. UnifiedKeyStore Protocol

```swift
/// Unified key store interface for common operations only
public protocol UnifiedKeyStore {
    // MARK: - Envelope Operations (Common)
    
    /// Encrypt data using envelope encryption
    func encryptWithEnvelope(data: Data, recipients: [EnvelopeRecipient]) throws -> Data
    
    /// Decrypt data using envelope decryption
    func decryptEnvelope(encryptedData: Data) throws -> Data
    
    // MARK: - Message Operations (Common)
    
    /// Encrypt message for a specific recipient
    func encryptMessage(data: Data, recipient: MessageRecipient) throws -> Data
    
    /// Decrypt message from a specific sender
    func decryptMessage(encryptedData: Data, sender: MessageSender) throws -> Data
    
    // MARK: - Network Operations (Common)
    
    /// Encrypt data for a specific network
    func encryptForNetwork(data: Data, networkId: String) throws -> Data
    
    /// Decrypt network data
    func decryptNetworkData(encryptedData: Data) throws -> Data
    
    // MARK: - State Management (Common)
    
    /// Get current keystore state
    func getKeystoreState() throws -> Int32
    
    /// Flush state to persistence
    func flushState() throws
    
    /// Wipe persistence data
    func wipePersistence() throws
}
```

### 2. Enums for Recipients and Senders

```swift
/// Envelope encryption recipients
public enum EnvelopeRecipient {
    case network(String)      // Network ID
    case profile(String)      // Profile label
    case publicKey(Data)     // Raw public key
}

/// Message recipients
public enum MessageRecipient {
    case publicKey(Data)     // Raw public key
    case node(String)        // Node ID
    case mobile(String)      // Mobile user ID
}

/// Message senders
public enum MessageSender {
    case publicKey(Data)     // Raw public key
    case node(String)        // Node ID
    case mobile(String)      // Mobile user ID
}
```

### 3. UnifiedKeyStoreManager

```swift
/// Manages a single key store instance for the entire app/node
public class UnifiedKeyStoreManager {
    private let ffiKeys: KeysFFI
    private var keyStore: UnifiedKeyStore?
    
    public init() {
        self.ffiKeys = KeysFFI()
    }
    
    /// Initialize the key store (platform-appropriate type)
    public func initialize() throws {
        #if os(iOS)
        try ffiKeys.initializeAsMobile()
        keyStore = MobileUnifiedKeyStore(ffiKeys: ffiKeys)
        #elseif os(macOS)
        try ffiKeys.initializeAsNode()
        keyStore = NodeUnifiedKeyStore(ffiKeys: ffiKeys)
        #else
        throw KeyStoreError.unsupportedPlatform
        #endif
    }
    
    /// Override key store type (for testing)
    public func initialize(as type: KeyStoreType) throws {
        switch type {
        case .mobile:
            try ffiKeys.initializeAsMobile()
            keyStore = MobileUnifiedKeyStore(ffiKeys: ffiKeys)
        case .node:
            try ffiKeys.initializeAsNode()
            keyStore = NodeUnifiedKeyStore(ffiKeys: ffiKeys)
        }
    }
    
    /// Get the unified key store interface
    public func getKeyStore() throws -> UnifiedKeyStore {
        guard let keyStore = keyStore else {
            throw KeyStoreError.notInitialized
        }
        return keyStore
    }
    
    /// Access underlying FFI for specific operations
    public var ffiKeys: KeysFFI { ffiKeys }
    
    /// Configure persistence
    public func configure(persistenceDirectory: URL, autoPersist: Bool) throws {
        try ffiKeys.setPersistenceDirectory(persistenceDirectory.path)
        try ffiKeys.enableAutoPersist(autoPersist)
    }
}

public enum KeyStoreType {
    case mobile
    case node
}

public enum KeyStoreError: Error {
    case notInitialized
    case unsupportedPlatform
    case operationNotSupported
}
```

### 4. MobileUnifiedKeyStore Implementation

```swift
/// Mobile key store implementation using unified API
public class MobileUnifiedKeyStore: UnifiedKeyStore {
    private let ffiKeys: KeysFFI
    
    public init(ffiKeys: KeysFFI) {
        self.ffiKeys = ffiKeys
    }
    
    // MARK: - UnifiedKeyStore Implementation
    
    public func encryptWithEnvelope(data: Data, recipients: [EnvelopeRecipient]) throws -> Data {
        // Route to mobile-specific FFI based on recipient type
        // Implementation details...
    }
    
    public func decryptEnvelope(encryptedData: Data) throws -> Data {
        return try ffiKeys.mobileDecryptEnvelope(encryptedData)
    }
    
    public func encryptMessage(data: Data, recipient: MessageRecipient) throws -> Data {
        // Route to appropriate mobile FFI method
        // Implementation details...
    }
    
    public func decryptMessage(encryptedData: Data, sender: MessageSender) throws -> Data {
        return try ffiKeys.mobileDecryptMessageFromNode(encryptedData)
    }
    
    public func encryptForNetwork(data: Data, networkId: String) throws -> Data {
        return try ffiKeys.mobileEncryptWithEnvelope(data: data, networkId: networkId)
    }
    
    public func decryptNetworkData(encryptedData: Data) throws -> Data {
        return try ffiKeys.decryptNetworkData(encryptedData)
    }
    
    public func getKeystoreState() throws -> Int32 {
        return try ffiKeys.mobileGetKeystoreState()
    }
    
    public func flushState() throws {
        try ffiKeys.flushState()
    }
    
    public func wipePersistence() throws {
        try ffiKeys.wipePersistence()
    }
}
```

### 5. NodeUnifiedKeyStore Implementation

```swift
/// Node key store implementation using unified API
public class NodeUnifiedKeyStore: UnifiedKeyStore {
    private let ffiKeys: KeysFFI
    
    public init(ffiKeys: KeysFFI) {
        self.ffiKeys = ffiKeys
    }
    
    // MARK: - UnifiedKeyStore Implementation
    
    public func encryptWithEnvelope(data: Data, recipients: [EnvelopeRecipient]) throws -> Data {
        // Route to node-specific FFI based on recipient type
        // Implementation details...
    }
    
    public func decryptEnvelope(encryptedData: Data) throws -> Data {
        return try ffiKeys.nodeDecryptEnvelope(encryptedData)
    }
    
    public func encryptMessage(data: Data, recipient: MessageRecipient) throws -> Data {
        // Route to appropriate node FFI method
        // Implementation details...
    }
    
    public func decryptMessage(encryptedData: Data, sender: MessageSender) throws -> Data {
        return try ffiKeys.decryptMessageFromMobile(encryptedData)
    }
    
    public func encryptForNetwork(data: Data, networkId: String) throws -> Data {
        return try ffiKeys.nodeEncryptWithEnvelope(data: data, networkId: networkId)
    }
    
    public func decryptNetworkData(encryptedData: Data) throws -> Data {
        return try ffiKeys.decryptNetworkData(encryptedData)
    }
    
    public func getKeystoreState() throws -> Int32 {
        return try ffiKeys.nodeGetKeystoreState()
    }
    
    public func flushState() throws {
        try ffiKeys.flushState()
    }
    
    public func wipePersistence() throws {
        try ffiKeys.wipePersistence()
    }
}
```

## Usage Patterns

### 1. iOS App Initialization

```swift
class iOSAppDelegate: UIResponder, UIApplicationDelegate {
    private var keyStoreManager: UnifiedKeyStoreManager!
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Initialize key store (automatically uses mobile on iOS)
        keyStoreManager = UnifiedKeyStoreManager()
        
        do {
            try keyStoreManager.initialize()
            
            // Perform mobile-specific initialization using direct FFI
            try performMobileInitialization()
            
            // Set up app components with unified API
            try setupAppComponents()
            
        } catch {
            print("Failed to initialize: \(error)")
            return false
        }
        
        return true
    }
    
    private func performMobileInitialization() throws {
        // Access underlying FFI for mobile-specific operations
        let ffiKeys = keyStoreManager.ffiKeys
        
        // Generate user root key (mobile-specific)
        try ffiKeys.mobileInitializeUserRootKey()
        
        // Set up persistence
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let keyStorePath = documentsPath.appendingPathComponent("KeyStore")
        try keyStoreManager.configure(persistenceDirectory: keyStorePath, autoPersist: true)
    }
    
    private func setupAppComponents() throws {
        let keyStore = try keyStoreManager.getKeyStore()
        
        // Pass unified key store to components
        let serializer = Serializer(keyStore: keyStore)
        let profileManager = ProfileManager(keyStore: keyStore)
        
        AppContext.shared.serializer = serializer
        AppContext.shared.profileManager = profileManager
    }
}
```

### 2. Profile Management (Mobile-Specific Operations)

```swift
class ProfileManager {
    private let keyStore: UnifiedKeyStore
    private let ffiKeys: KeysFFI
    
    init(keyStore: UnifiedKeyStore, ffiKeys: KeysFFI) {
        self.keyStore = keyStore
        self.ffiKeys = ffiKeys
    }
    
    func createProfile(label: String) throws -> Profile {
        // Use mobile-specific FFI directly
        let profileKey = try ffiKeys.mobileDeriveUserProfileKey(label: label)
        
        let profile = Profile(
            id: UUID().uuidString,
            label: label,
            publicKey: profileKey,
            createdAt: Date()
        )
        
        // Store using unified API
        try saveProfile(profile)
        return profile
    }
    
    func encryptDataForProfile(_ data: Data, profileLabel: String) throws -> Data {
        // Use unified API
        return try keyStore.encryptWithEnvelope(
            data: data,
            recipients: [.profile(profileLabel)]
        )
    }
    
    private func saveProfile(_ profile: Profile) throws {
        let profileData = try JSONEncoder().encode(profile)
        let encryptedData = try keyStore.encryptWithEnvelope(
            data: profileData,
            recipients: [.profile(profile.label)]
        )
        
        let profilePath = getProfilePath(for: profile.id)
        try encryptedData.write(to: profilePath)
    }
    
    private func getProfilePath(for id: String) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("profiles/\(id).encrypted")
    }
}
```

### 3. Serializer Usage (Common API)

```swift
class Serializer {
    private let keyStore: UnifiedKeyStore
    
    init(keyStore: UnifiedKeyStore) {
        self.keyStore = keyStore
    }
    
    func encrypt(data: Data, for networkId: String) throws -> Data {
        // Uses unified API - no need to know about mobile vs node
        return try keyStore.encryptForNetwork(data: data, networkId: networkId)
    }
    
    func decrypt(encryptedData: Data) throws -> Data {
        // Uses unified API
        return try keyStore.decryptNetworkData(encryptedData)
    }
    
    func encryptMessage(data: Data, for recipient: MessageRecipient) throws -> Data {
        // Uses unified API
        return try keyStore.encryptMessage(data: data, recipient: recipient)
    }
}
```

### 4. Node Package Usage

```swift
class NodePackage {
    private let keyStore: UnifiedKeyStore
    private let ffiKeys: KeysFFI
    
    init(keyStore: UnifiedKeyStore, ffiKeys: KeysFFI) {
        self.keyStore = keyStore
        self.ffiKeys = ffiKeys
    }
    
    func setupNode() throws {
        // Use node-specific FFI directly
        let csr = try ffiKeys.nodeGenerateCSR()
        
        // Store CSR using unified API
        try storeCSR(csr)
    }
    
    func encryptDataForNetwork(_ data: Data, networkId: String) throws -> Data {
        // Use unified API
        return try keyStore.encryptForNetwork(data: data, networkId: networkId)
    }
    
    private func storeCSR(_ csr: Data) throws {
        let encryptedCSR = try keyStore.encryptWithEnvelope(
            data: csr,
            recipients: [.profile("node-setup")]
        )
        
        let csrPath = getCSRPath()
        try encryptedCSR.write(to: csrPath)
    }
    
    private func getCSRPath() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("node-setup.csr.encrypted")
    }
}
```

## Key Benefits

1. **Single Instance**: One key store per app/node, shared between common API and specific operations
2. **Common Operations Only**: Unified API only includes operations both mobile and node support
3. **Direct FFI Access**: Mobile-specific operations accessed directly when needed
4. **Platform Defaults**: Automatic mobile/node selection based on platform
5. **Minimal Abstraction**: Only abstracts what's needed for consumers
6. **Easy Testing**: Can override key store type for testing scenarios

## Implementation Phases

1. **Phase 1**: Core interfaces and enums
2. **Phase 2**: MobileUnifiedKeyStore implementation
3. **Phase 3**: NodeUnifiedKeyStore implementation
4. **Phase 4**: UnifiedKeyStoreManager
5. **Phase 5**: Integration with serializer and node packages
6. **Phase 6**: Testing and validation

## Conclusion

This simplified design provides exactly what's needed:
- **Common operations** abstracted for serializer/node packages
- **Mobile-specific operations** accessible directly through FFI
- **Single key store instance** shared across the app
- **Platform-appropriate defaults** with testing flexibility
- **Minimal complexity** matching the Rust architecture

The unified API handles only the common operations that both mobile and node support, while maintaining direct access to the underlying FFI for specific operations when needed.

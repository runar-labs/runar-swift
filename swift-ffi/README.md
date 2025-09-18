# Swift FFI

A Swift wrapper for the Runar Rust FFI library, providing a native Swift interface to cryptographic operations, key management, and network protocols.

## Overview

This library provides Swift bindings for the Runar Rust FFI, enabling Swift applications to leverage Rust's cryptographic capabilities while maintaining idiomatic Swift APIs. The library supports both node and mobile key management, certificate operations, encryption/decryption, and network protocols.

## Architecture

### Core Components

- **KeysHandle**: Main interface for key management operations
- **CANode**: Certificate Authority node operations
- **CAServer**: Certificate Authority server functionality
- **CAClient**: Certificate Authority client operations
- **TransportHandle**: QUIC transport operations
- **DiscoveryHandle**: Network discovery functionality

### Error Handling

All operations use a consistent error handling pattern with the `FFIError` enum:

```swift
public enum FFIError: Error, LocalizedError {
    case operationFailed(String)
    case invalidParameter(String)
    case memoryError(String)
    case networkError(String)
}
```

### Memory Management

The library automatically manages memory for FFI operations:
- All FFI-allocated memory is copied to Swift `Data` objects
- Memory is freed using appropriate FFI cleanup functions
- Handles are automatically freed when Swift objects are deallocated

## Key Features

### Key Management

- **Node Keys**: Full node key management with certificate operations
- **Mobile Keys**: Mobile device key management and certificate processing
- **Symmetric Keys**: Local data encryption with symmetric keys
- **Profile Keys**: User profile key derivation and management

### Certificate Operations

- **CSR Generation**: Certificate signing request generation
- **Certificate Installation**: Certificate installation and validation
- **Certificate Status**: Certificate status and serial number retrieval
- **Peer Validation**: Peer certificate validation

### Encryption & Decryption

- **Envelope Encryption**: Encrypt data for multiple recipients
- **Local Data Encryption**: Encrypt/decrypt local data with symmetric keys
- **Message Encryption**: Encrypt messages between mobile and node
- **Network Encryption**: Encrypt data for network transmission

### Persistence & Keystore

- **Persistence Directory**: Configure key storage location
- **Auto-Persistence**: Enable/disable automatic key persistence
- **Keystore Capabilities**: Query keystore capabilities
- **Apple Device Keystore**: Integration with Apple's Secure Enclave

### Network Operations

- **QUIC Transport**: High-performance network transport
- **Discovery**: Network peer discovery
- **CA Operations**: Certificate Authority server and client operations

## Usage Examples

### Basic Key Management

```swift
import SwiftFFI

// Create and initialize keys handle
let keys = try KeysHandle()
try keys.initializeAsNode()
try keys.nodeGenerateKeys()

// Generate CSR
let csr = try keys.generateCsrSetupToken()

// Get node public key
let publicKey = try keys.getNodePublicKey()
```

### Mobile Key Operations

```swift
// Initialize as mobile
let mobileKeys = try KeysHandle()
try mobileKeys.initializeAsMobile()
try mobileKeys.mobileInitializeUserRootKey()

// Get user public key
let userPublicKey = try mobileKeys.mobileGetUserPublicKey()

// Derive profile key
let profileKey = try mobileKeys.mobileDeriveUserProfileKey(label: "personal")
```

### Encryption Operations

```swift
// Encrypt local data
let data = "Secret message".data(using: .utf8)!
let encrypted = try keys.encryptLocalData(data)
let decrypted = try keys.decryptLocalData(encrypted)

// Encrypt with envelope
let profileKeys = [try keys.deriveUserProfileKey(label: "personal")]
let envelope = try keys.encryptWithEnvelope(plaintext: data, profileKeys: profileKeys)
```

### Certificate Authority Operations

```swift
// Create CA node
let caNode = try CANode.create()

// Set up CA node
let setupParams = CANodeManager.CANodeSetupParams(
    caNode: caNode.ffiHandle,
    rootCaSubject: "CN=Root CA",
    issuingCaSubject: "CN=Issuing CA",
    validityDays: 365,
    issuingCaSerial: 1,
    eaPublicKeys: eaKeysData,
    networkId: "test-network"
)
try caNode.setupComplete(params: setupParams)

// Create CA server
let serverConfig = CaServerConfig(
    bootstrapBind: "127.0.0.1:8080",
    authenticatedBind: "127.0.0.1:8081",
    networkId: "test-network",
    rateLimitPerMinute: 100,
    rateLimitPerHour: 1000
)
let sharedCaNode = try caNode.createShared()
let caServer = try CAServer.create(config: serverConfig, sharedCaNode: sharedCaNode)
```

### Transport Operations

```swift
// Create transport
let transportOptions = QuicTransportOptionsCbor(
    bindAddr: "127.0.0.1:0",
    handshakeTimeoutMs: 5000,
    maxMessageSize: 1024
)
let optionsCbor = try CBORHelper.encodeTransportOptions(transportOptions)
let transport = try TransportHandle.create(keys: keys, optionsCbor: optionsCbor)

// Start transport
try transport.start()

// Send request
let requestParams = TransportRequestParams(
    path: "/api/test",
    correlationId: UUID().uuidString,
    payload: "Hello, World!".data(using: .utf8)!,
    destPeerId: "peer-id"
)
let requestCbor = try CBORHelper.encodeTransportRequestParams(requestParams)
try transport.request(requestCbor: requestCbor)
```

## Error Handling

All operations can throw `FFIError` with specific error types:

```swift
do {
    let result = try keys.someOperation()
} catch FFIError.invalidParameter(let message) {
    // Handle invalid parameter error
} catch FFIError.operationFailed(let message) {
    // Handle operation failure
} catch {
    // Handle other errors
}
```

## Thread Safety

**Important**: The library is not thread-safe. All operations should be performed on the same queue/actor to ensure thread safety:

```swift
// Good: Use a serial queue
let keysQueue = DispatchQueue(label: "keys.queue")
keysQueue.async {
    try keys.someOperation()
}

// Good: Use an actor
@MainActor
func performKeyOperation() {
    try keys.someOperation()
}
```

## Input Validation

The library includes comprehensive input validation:

- **Data Size Limits**: Prevents excessive memory usage
- **String Length Limits**: Prevents buffer overflow attacks
- **Empty Parameter Validation**: Ensures required parameters are provided
- **Handle Validation**: Ensures handles are properly initialized

## Memory Model

The library follows a copy-and-free memory model:

1. **Input Data**: Swift `Data` objects are passed to FFI functions
2. **Output Data**: FFI-allocated memory is copied to Swift `Data` objects
3. **Cleanup**: FFI memory is automatically freed using appropriate cleanup functions
4. **Handles**: Rust handles are automatically freed when Swift objects are deallocated

## Testing

The library includes comprehensive tests covering:

- **Unit Tests**: Individual API functionality
- **Integration Tests**: End-to-end workflows
- **Error Handling**: Error conditions and edge cases
- **Performance Tests**: Performance characteristics
- **Concurrency Tests**: Thread safety validation

Run tests with:

```bash
swift test
```

## Dependencies

- **SwiftCBOR**: CBOR encoding/decoding
- **SwiftCommon**: Common utilities and logging
- **CRunarFFI**: Rust FFI bindings

## Building

The library requires the Rust FFI library to be built first:

```bash
# Build Rust FFI
cd runar-rust
cargo build --release

# Build Swift package
swift build
```

## API Reference

### KeysHandle

Main interface for key management operations.

#### Initialization
- `init()` - Create new keys handle
- `initializeAsNode()` - Initialize as node
- `initializeAsMobile()` - Initialize as mobile

#### Key Operations
- `nodeGenerateKeys()` - Generate node keys
- `getNodePublicKey()` - Get node public key
- `getNodeAgreementPublicKey()` - Get node agreement public key
- `getNodeId()` - Get node ID

#### Certificate Operations
- `generateCsrSetupToken()` - Generate CSR
- `installCertificate(_:)` - Install certificate
- `getCertificateStatus()` - Get certificate status
- `getCertificateSerial()` - Get certificate serial

#### Encryption Operations
- `encryptLocalData(_:)` - Encrypt local data
- `decryptLocalData(_:)` - Decrypt local data
- `encryptWithEnvelope(plaintext:profileKeys:)` - Encrypt with envelope
- `decryptWithProfile(envelope:profileId:)` - Decrypt with profile

#### Persistence Operations
- `setPersistenceDirectory(_:)` - Set persistence directory
- `enableAutoPersistence(_:)` - Enable auto-persistence
- `wipePersistence()` - Wipe persisted data
- `flushState()` - Flush state to persistence

### CANode

Certificate Authority node operations.

#### Lifecycle
- `create()` - Create CA node
- `setupComplete(params:)` - Complete CA setup
- `createShared()` - Create shared CA node

#### Operations
- `getRootCACertificate()` - Get root CA certificate
- `getIssuingCACertificate()` - Get issuing CA certificate
- `handleCRL(networkId:)` - Handle CRL request
- `revokeToken(_:)` - Revoke enrollment token

### CAServer

Certificate Authority server operations.

#### Lifecycle
- `create(config:sharedCaNode:)` - Create CA server
- `start()` - Start server
- `stop()` - Stop server

#### Operations
- `bootstrapAddress()` - Get bootstrap address
- `authenticatedAddress()` - Get authenticated address
- `configureAdminSkis(_:)` - Configure admin SKIs

### CAClient

Certificate Authority client operations.

#### Lifecycle
- `init(config:nodeKeys:)` - Create CA client

#### Operations
- `enroll(bootstrapAddress:request:)` - Enroll certificate
- `renew(authenticatedAddress:request:)` - Renew certificate
- `revoke(authenticatedAddress:request:)` - Revoke certificate
- `getStatus(authenticatedAddress:networkId:)` - Get certificate status
- `getChain(bootstrapAddress:networkId:)` - Get certificate chain
- `getCrl(authenticatedAddress:networkId:)` - Get CRL

### TransportHandle

QUIC transport operations.

#### Lifecycle
- `create(keys:optionsCbor:)` - Create transport
- `start()` - Start transport
- `stop()` - Stop transport

#### Operations
- `request(requestCbor:)` - Send request
- `publish(publishCbor:)` - Publish event
- `completeRequest(completeCbor:)` - Complete request
- `pollEvent()` - Poll for events
- `connectPeer(peerInfoCbor:)` - Connect to peer
- `disconnectPeer(peerNodeId:)` - Disconnect from peer
- `isConnected(peerNodeId:)` - Check connection status

## Contributing

1. Follow Swift coding standards
2. Add comprehensive tests for new features
3. Update documentation for API changes
4. Ensure thread safety considerations
5. Validate input parameters

## License

This project is licensed under the same terms as the main Runar project.

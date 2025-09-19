# Unified Swift KeyManager Design (swift-ffi)

## Motivation

The current `KeysHandle` exposes mixed node and mobile methods and inconsistent naming such as `encryptWithEnvelope` (node) vs `mobileEncryptWithEnvelope` (mobile). Higher layers like `swift-serializer` must be agnostic of the underlying role (node vs mobile) but need a single, stable API. We will introduce a minimal common Swift-facing interface for serializer and distinct role-specific APIs for node and mobile. No transitional or backward-compat layers — clean refactor only.

## Goals

- Provide a single common API surface usable by serializer without role knowledge.
- Expose clear Node-only and Mobile-only APIs for components that know the role.
- Map 1:1 to Rust FFI exports without fallbacks or hidden behavior.
- Production-grade error handling and memory safety.

## Non-Goals

- No deprecations or compatibility layers.
- No role switching or runtime role checks: role-specific types prevent misuse.

## Proposed Swift API

### Common Key Manager (shared by both roles)

Single common capability surface (also used by serializer). Implemented by both node and mobile managers.

```swift
public struct KeystoreCapabilities: Sendable {
    public let version: UInt32
    public let flags: UInt32
}

public protocol CommonKeyManager: Sendable {
    // Envelope crypto (serializer-critical)
    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profilePublicKeys: [Data]) throws -> Data
    func decryptEnvelope(envelopeData: Data) throws -> Data

    // Symmetric key management
    func ensureSymmetricKey(name: String) throws -> Data
    func encryptLocalData(data: Data, keyName: String) throws -> Data
    func decryptLocalData(encryptedData: Data, keyName: String) throws -> Data

    // Persistence & keystore
    func setPersistenceDirectory(_ path: String) throws
    func enableAutoPersistence(_ enabled: Bool) throws
    func wipePersistence() throws
    func getKeystoreCapabilities() throws -> KeystoreCapabilities
    func flushState() throws
    func registerAppleDeviceKeystore(label: String) throws

    // General message crypto (role-agnostic FFI)
    func encryptForPublicKey(data: Data, publicKey: Data) throws -> Data
    func encryptForNetwork(data: Data, networkPublicKey: Data) throws -> Data
    func decryptNetworkData(encryptedEnvelope: Data) throws -> Data
}
```

### Node-only API

```swift
public protocol NodeOnly: CommonKeyManager, Sendable {
    func hasKeys() throws -> Bool
    func generateKeys() throws
    func generateCsrSetupToken() throws -> Data
    func installCertificate(_ certMessage: Data) throws
    func getQuicCertificateConfig() throws -> Data
    func getNodeCertificate() throws -> Data
    func getNodePublicKey() throws -> Data
    func getAgreementPublicKey() throws -> Data
    func setLocalNodeInfo(_ nodeInfoCbor: Data) throws

    // Profile keys (node authority)
    func deriveUserProfileKey(label: String) throws -> Data
    func decryptWithProfile(envelopeData: Data, profileId: String) throws -> Data
    func installProfilePublicKey(_ publicKey: Data) throws
    func getProfilePublicKey(label: String) throws -> (publicKey: Data?, exists: Bool)

    // Network keys (node side)
    func installNetworkKey(_ networkKeyMessage: Data) throws
    func getNetworkAgreement(networkPublicKey: Data) throws -> Data
    func hasNetworkPrivateKey(networkPublicKey: Data) throws -> Bool

    // Message crypto (node <-> mobile)
    func encryptMessageForMobile(data: Data, mobilePublicKey: Data) throws -> Data
    func decryptMessageFromMobile(encryptedData: Data) throws -> Data
}
```

### Mobile-only API

```swift
public protocol MobileOnly: CommonKeyManager, Sendable {
    func initializeUserRootKey() throws
    func getUserPublicKey() throws -> Data

    // Profile key derivation (mobile may derive; install/listing are node-only)
    func deriveUserProfileKey(label: String) throws -> Data

    // Network key operations (mobile side)
    func installNetworkPublicKey(_ networkPublicKey: Data) throws
    func generateNetworkDataKey() throws -> Data
    func hasNetworkPrivateKey(networkPublicKey: Data) throws -> Bool
    func createNetworkKeyMessage(networkPublicKey: Data, nodeAgreementPublicKey: Data) throws -> Data

    // Setup/cert flows
    func processSetupToken(_ setupToken: Data) throws -> Data
    func fromEnrollResponse(_ response: Data) throws -> Data
    func fromRenewResponse(_ response: Data) throws -> Data

    // Message crypto (mobile <-> node)
    func encryptMessageForNode(data: Data, nodeAgreementPublicKey: Data) throws -> Data
    func decryptMessageFromNode(encryptedData: Data) throws -> Data
}
```

## Concrete Types

Two concrete, role-specific managers. Each creates and owns its FFI handle and implements `CommonKeyManager` plus its role protocol.

```swift
public final class NodeKeyManager: NodeOnly { /* FFI-backed */ }
public final class MobileKeyManager: MobileOnly { /* FFI-backed */ }
```

Initialization:
- NodeKeyManager: `rn_keys_new` then `rn_keys_init_as_node`
- MobileKeyManager: `rn_keys_new` then `rn_keys_init_as_mobile`

No type exposes APIs from the opposite role, so misuse is prevented at compile-time.

## FFI Mapping

### CommonKeyManager (both types)

- Envelope crypto
  - encryptWithEnvelope → node: `rn_keys_node_encrypt_with_envelope`, mobile: `rn_keys_mobile_encrypt_with_envelope`
  - decryptEnvelope → node: `rn_keys_node_decrypt_envelope`, mobile: `rn_keys_mobile_decrypt_envelope`

- Symmetric keys
  - ensureSymmetricKey → `rn_keys_ensure_symmetric_key`
  - encryptLocalData → `rn_keys_encrypt_local_data`
  - decryptLocalData → `rn_keys_decrypt_local_data`

- Persistence & keystore
  - setPersistenceDirectory → `rn_keys_set_persistence_dir`
  - enableAutoPersistence → `rn_keys_enable_auto_persist`
  - wipePersistence → `rn_keys_wipe_persistence`
  - getKeystoreCapabilities → `rn_keys_get_keystore_caps`
  - flushState → `rn_keys_flush_state`
  - registerAppleDeviceKeystore → `rn_keys_register_apple_device_keystore`

- General message crypto
  - encryptForPublicKey → `rn_keys_encrypt_for_public_key`
  - encryptForNetwork → `rn_keys_encrypt_for_network`
  - decryptNetworkData → `rn_keys_decrypt_network_data`

### Node-only

- hasKeys → `rn_keys_node_has_keys`
- generateKeys → `rn_keys_node_generate_keys`
- generateCsrSetupToken → `rn_keys_node_generate_csr`
- installCertificate → `rn_keys_node_install_certificate`
- getQuicCertificateConfig → `rn_keys_node_get_quic_certificate_config`
- getNodeCertificate → `rn_keys_node_get_node_certificate`
- getNodePublicKey → `rn_keys_node_get_public_key`
- getAgreementPublicKey → `rn_keys_node_get_agreement_public_key`
- setLocalNodeInfo → `rn_keys_set_local_node_info`
- deriveUserProfileKey → `rn_keys_node_derive_user_profile_key`
- decryptWithProfile → `rn_keys_node_decrypt_with_profile`
- installProfilePublicKey → `rn_keys_node_install_profile_public_key`
- getProfilePublicKey → `rn_keys_node_get_profile_public_key_by_label`
- installNetworkKey → `rn_keys_node_install_network_key`
- getNetworkAgreement → `rn_keys_node_get_network_agreement`
- hasNetworkPrivateKey → `rn_keys_node_has_network_private_key`
- encryptMessageForMobile → `rn_keys_encrypt_message_for_mobile`
- decryptMessageFromMobile → `rn_keys_decrypt_message_from_mobile`

### Mobile-only

- initializeUserRootKey → `rn_keys_mobile_initialize_user_root_key`
- getUserPublicKey → `rn_keys_mobile_get_user_public_key`
- deriveUserProfileKey → `rn_keys_mobile_derive_user_profile_key`
- installNetworkPublicKey → `rn_keys_mobile_install_network_public_key`
- generateNetworkDataKey → `rn_keys_mobile_generate_network_data_key`
- hasNetworkPrivateKey → `rn_keys_mobile_has_network_private_key`
- createNetworkKeyMessage → `rn_keys_mobile_create_network_key_message`
- processSetupToken → `rn_keys_mobile_process_setup_token`
- fromEnrollResponse → `rn_keys_mobile_from_enroll_response`
- fromRenewResponse → `rn_keys_mobile_from_renew_response`
- encryptMessageForNode → `rn_keys_encrypt_message_for_node`
- decryptMessageFromNode → `rn_keys_mobile_decrypt_message_from_node`

## Error Model

- Role separation is enforced by types; all FFI errors propagate with original codes/messages. No fallbacks.

## Serializer Integration

- Serializer depends only on `CommonKeyManager`.
- Node-only `decryptWithProfile` remains in NodeOnly; any use must live in node-aware code.

## Refactor Plan (swift-ffi)

1. Add protocols: `CommonKeyManager`, `NodeOnly`, `MobileOnly`.
2. Implement `NodeKeyManager` and `MobileKeyManager` types:
   - Own FFI handle lifecycle (`rn_keys_new`/`rn_keys_free`), init as node/mobile.
   - Implement common and role-specific methods with proper memory handling.
3. Remove `KeysHandle` entirely. Replace all usages with role-specific types or `CommonKeyManager` as appropriate.
4. Unify method names: remove `mobile*` prefixes. Provide only the common names on respective types.
5. Update transport/discovery and other helpers to accept the appropriate role-specific type or `CommonKeyManager` where only common functions are needed.
6. Update serializer to depend only on `CommonKeyManager` and stop invoking node-only APIs.
7. Run SwiftLint/SwiftFormat and fix violations.
8. Unskip tests for symmetric keys, persistence, message crypto after implementing these methods.

## Test Strategy

- Create tests for both managers exercising common methods with vectors and ensuring parity.
- Node-only tests cover certificates, CSR, profile decrypt, network agreement, etc.
- Mobile-only tests cover setup token processing, network key message, etc.
- Integration tests in serializer with both `NodeKeyManager` and `MobileKeyManager` via `CommonKeyManager`.

## Security and Determinism

- Strict pointer and memory management (use `defer` frees for FFI outputs).
- No hidden behavior or role fallbacks.

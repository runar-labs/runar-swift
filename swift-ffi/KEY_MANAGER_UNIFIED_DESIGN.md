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

### Common Envelope Crypto (role-agnostic)

Minimal surface used by serializer. Implemented by both node and mobile managers.

```swift
public protocol EnvelopeCryptoCommon: Sendable {
    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profilePublicKeys: [Data]) throws -> Data
    func decryptEnvelope(envelopeData: Data) throws -> Data
}
```

Notes:
- Only truly common methods are included. Node-only features like `decryptWithProfile` are not part of the common protocol and remain in the node API.

### Node-only API

```swift
public protocol NodeOnly: Sendable {
    // Also conforms to EnvelopeCryptoCommon
    func hasKeys() throws -> Bool
    func generateKeys() throws
    func generateCsrSetupToken() throws -> Data
    func installCertificate(_ certMessage: Data) throws
    func getQuicCertificateConfig() throws -> Data
    func getNodeCertificate() throws -> Data
    func getNodePublicKey() throws -> Data
    func deriveUserProfileKey(label: String) throws -> Data
    func decryptWithProfile(envelopeData: Data, profileId: String) throws -> Data
    func installProfilePublicKey(_ publicKey: Data) throws
    func getProfilePublicKey(label: String) throws -> (publicKey: Data, exists: Bool)
    func getCertificateStatus() throws -> Int32
    func getCertificateSerial() throws -> String
    func validatePeerCertificate(_ cert: Data) throws
    func installNetworkKey(_ networkKeyMessage: Data) throws
    func getNetworkAgreement(networkPublicKey: Data) throws -> Data
    func hasNetworkPrivateKey(networkPublicKey: Data) throws -> Bool
}
```

### Mobile-only API

```swift
public protocol MobileOnly: Sendable {
    // Also conforms to EnvelopeCryptoCommon
    func initializeUserRootKey() throws
    func getUserPublicKey() throws -> Data
    func deriveUserProfileKey(label: String) throws -> Data
    func installNetworkPublicKey(_ networkPublicKey: Data) throws
    func generateNetworkDataKey() throws -> Data
    func hasNetworkPrivateKey(networkPublicKey: Data) throws -> Bool
    func createNetworkKeyMessage(networkPublicKey: Data, nodeAgreementPublicKey: Data) throws -> Data
    func processSetupToken(_ setupToken: Data) throws -> Data
    func fromEnrollResponse(_ response: Data) throws -> Data
    func fromRenewResponse(_ response: Data) throws -> Data
}
```

## Concrete Types

Two concrete, role-specific managers. Each creates and owns its FFI handle and implements `EnvelopeCryptoCommon` plus its role protocol.

```swift
public final class NodeKeyManager: NodeOnly, EnvelopeCryptoCommon { /* FFI-backed */ }
public final class MobileKeyManager: MobileOnly, EnvelopeCryptoCommon { /* FFI-backed */ }
```

Initialization:
- NodeKeyManager: `rn_keys_new` then `rn_keys_init_as_node`
- MobileKeyManager: `rn_keys_new` then `rn_keys_init_as_mobile`

No type exposes APIs from the opposite role, so misuse is prevented at compile-time.

## FFI Mapping

### Common methods (both types implement)

- encryptWithEnvelope
  - Node: `rn_keys_node_encrypt_with_envelope`
  - Mobile: `rn_keys_mobile_encrypt_with_envelope`
- decryptEnvelope
  - Node: `rn_keys_node_decrypt_envelope`
  - Mobile: `rn_keys_mobile_decrypt_envelope`

### Node-only

- hasKeys → `rn_keys_node_has_keys`
- generateKeys → `rn_keys_node_generate_keys`
- generateCsrSetupToken → `rn_keys_node_generate_csr`
- installCertificate → `rn_keys_node_install_certificate`
- getQuicCertificateConfig → `rn_keys_node_get_quic_certificate_config`
- getNodeCertificate → `rn_keys_node_get_node_certificate`
- getNodePublicKey → `rn_keys_node_get_public_key`
- deriveUserProfileKey → `rn_keys_node_derive_user_profile_key`
- decryptWithProfile → `rn_keys_node_decrypt_with_profile`
- installProfilePublicKey → `rn_keys_node_install_profile_public_key`
- getProfilePublicKey → `rn_keys_node_get_profile_public_key_by_label`
- getCertificateStatus → `rn_keys_node_get_certificate_status`
- getCertificateSerial → `rn_keys_node_get_certificate_serial`
- validatePeerCertificate → `rn_keys_node_validate_peer_certificate`
- installNetworkKey → `rn_keys_node_install_network_key`
- getNetworkAgreement → `rn_keys_node_get_network_agreement`
- hasNetworkPrivateKey → `rn_keys_node_has_network_private_key`

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

## Error Model

- No role errors at runtime (types prevent it). All FFI errors propagate with original codes/messages.
- No fallbacks; deterministic behavior only.

## Serializer Integration

- Serializer depends only on `EnvelopeCryptoCommon`.
- Wherever serializer currently calls node-only decryptWithProfile, migrate to use the common decryptEnvelope flow or move that functionality into code that depends on `NodeOnly` explicitly.
- The concrete instance passed to serializer can be either `NodeKeyManager` or `MobileKeyManager` and must satisfy `EnvelopeCryptoCommon`.

## Refactor Plan (swift-ffi)

1. Add protocols: `EnvelopeCryptoCommon`, `NodeOnly`, `MobileOnly`.
2. Implement `NodeKeyManager` and `MobileKeyManager` types:
   - Own FFI handle lifecycle (`rn_keys_new`/`rn_keys_free`), init as node/mobile.
   - Implement common and role-specific methods with proper memory handling.
3. Remove `KeysHandle` entirely. Replace all usages with role-specific types or `EnvelopeCryptoCommon` as appropriate.
4. Unify method names: remove `mobile*` prefixes. Provide only the common names on respective types.
5. Update transport/discovery and other helpers to accept the appropriate role-specific type or `EnvelopeCryptoCommon` where only common functions are needed.
6. Update serializer to depend only on `EnvelopeCryptoCommon` and stop invoking node-only APIs.
7. Run SwiftLint/SwiftFormat and fix violations.

## Test Strategy

- Create tests for both managers exercising common methods with vectors and ensuring parity.
- Node-only tests cover certificates, CSR, profile decrypt, network agreement, etc.
- Mobile-only tests cover setup token processing, network key message, etc.
- Integration tests in serializer with both `NodeKeyManager` and `MobileKeyManager` via `EnvelopeCryptoCommon`.

## Security and Determinism

- Strict pointer and memory management (use `defer` frees for FFI outputs).
- No hidden behavior or role fallbacks.

# Unified Swift KeyManager Design (swift-ffi)

## Motivation

The current `KeysHandle` exposes mixed node and mobile methods and inconsistent naming such as `encryptWithEnvelope` (node) vs `mobileEncryptWithEnvelope` (mobile). Higher layers like `swift-serializer` must be agnostic of the underlying role (node vs mobile) but need a single, stable API. We will introduce a minimal common Swift-facing interface for serializer and distinct role-specific APIs for node and mobile. No transitional or backward-compat layers — clean refactor only.

## Goals

- Provide a single common API surface usable by serializer without role knowledge.
- Expose clear Node-only and Mobile-only APIs for components that know the role.
- Map 1:1 to Rust FFI exports without fallbacks or hidden behavior.
- Production-grade error handling and memory safety.
- Actor-based concurrency with async/await for thread safety; no `@unchecked Sendable`.

## Non-Goals

- No deprecations or compatibility layers.
- No role switching or runtime role checks: role-specific types prevent misuse.

## Concurrency Model

- Use Swift actors for key manager implementations: `NodeKeyManager` and `MobileKeyManager` are actors.
- All public API methods are `async throws`. Cross-actor calls require `await`, removing the need for `@unchecked Sendable`.
- FFI calls remain synchronous internally but are isolated within actor execution, ensuring thread safety of the underlying handle.

> Swift 6 FFI Concurrency Guidance (see section below) governs how we write actor methods and FFI helpers to satisfy strict concurrency rules while safely calling C/Rust.

## Proposed Swift API

### Common Key Manager (shared by both roles)

Single common capability surface (also used by serializer). Implemented by both node and mobile managers.

```swift
public struct KeystoreCapabilities {
    public let version: UInt32
    public let flags: UInt32
}

public protocol CommonKeyManager {
    // Envelope crypto (serializer-critical)
    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profilePublicKeys: [Data]) async throws -> Data
    func decryptEnvelope(envelopeData: Data) async throws -> Data

    // Symmetric key management (default-key based)
    func ensureSymmetricKey(name: String) async throws -> Data
    func encryptLocalData(data: Data) async throws -> Data
    func decryptLocalData(encryptedData: Data) async throws -> Data

    // Persistence & keystore
    func setPersistenceDirectory(_ path: String) async throws
    func enableAutoPersistence(_ enabled: Bool) async throws
    func wipePersistence() async throws
    func getKeystoreCapabilities() async throws -> KeystoreCapabilities
    func flushState() async throws
    func registerAppleDeviceKeystore(label: String) async throws

    // General message crypto (role-agnostic FFI)
    func encryptForNetwork(data: Data, networkPublicKey: Data) async throws -> Data
    func decryptNetworkData(encryptedEnvelope: Data) async throws -> Data
}
```

Notes:
- `encryptLocalData`/`decryptLocalData` do not take a key name because the underlying FFI operates on the default symmetric key. `ensureSymmetricKey(name:)` can be used to ensure existence, but subsequent local data operations do not select by name.
- Actor methods must not suspend during FFI pointer usage; see Swift 6 guidance below.

### Node-only API

```swift
public protocol NodeOnly: CommonKeyManager {
    func hasKeys() async throws -> Bool
    func generateKeys() async throws
    func generateCsrSetupToken() async throws -> Data
    func installCertificate(_ certMessage: Data) async throws
    func getQuicCertificateConfig() async throws -> Data
    func getNodeCertificate() async throws -> Data
    func getNodePublicKey() async throws -> Data
    func getAgreementPublicKey() async throws -> Data
    func setLocalNodeInfo(_ nodeInfoCbor: Data) async throws

    // Profile keys (node authority)
    func deriveUserProfileKey(label: String) async throws -> Data
    func decryptWithProfile(envelopeData: Data, profileId: String) async throws -> Data
    func installProfilePublicKey(_ publicKey: Data) async throws
    func getProfilePublicKey(label: String) async throws -> (publicKey: Data?, exists: Bool)

    // Network keys (node side)
    func installNetworkKey(_ networkKeyMessage: Data) async throws
    func getNetworkAgreement(networkPublicKey: Data) async throws -> Data
    func hasNetworkPrivateKey(networkPublicKey: Data) async throws -> Bool

    // Message crypto (node <-> mobile)
    func encryptMessageForMobile(data: Data, mobilePublicKey: Data) async throws -> Data
    func decryptMessageFromMobile(encryptedData: Data) async throws -> Data
}
```

> Implementation note: obtain `let handle = self.handle` up-front and pass that local to nonisolated FFI helpers. Do not reference `self` inside closures passed to FFI wrappers.

### Mobile-only API

```swift
public protocol MobileOnly: CommonKeyManager {
    func initializeUserRootKey() async throws
    func getUserPublicKey() async throws -> Data

    // Profile key derivation (mobile may derive; install/listing are node-only)
    func deriveUserProfileKey(label: String) async throws -> Data

    // Network key operations (mobile side)
    func installNetworkPublicKey(_ networkPublicKey: Data) async throws
    func generateNetworkDataKey() async throws -> Data
    func hasNetworkPrivateKey(networkPublicKey: Data) async throws -> Bool
    func createNetworkKeyMessage(networkPublicKey: Data, nodeAgreementPublicKey: Data) async throws -> Data

    // Setup/cert flows
    func processSetupToken(_ setupToken: Data) async throws -> Data
    func fromEnrollResponse(_ response: Data) async throws -> Data
    func fromRenewResponse(_ response: Data) async throws -> Data

    // Message crypto (mobile <-> node)
    func encryptMessageForNode(data: Data, nodeAgreementPublicKey: Data) async throws -> Data
    func decryptMessageFromNode(encryptedData: Data) async throws -> Data
}
```

## Profile Key Management Responsibilities

- Mobile can derive profile keys only: `deriveUserProfileKey(label:)`.
- Node has authority over profile key registry: `installProfilePublicKey(_:)`, `getProfilePublicKey(label:)`, and `decryptWithProfile(...)` are node-only.
- These methods are intentionally NOT part of `CommonKeyManager`, ensuring compile-time separation and exact parity with Rust:
  - Rust FFI provides `rn_keys_mobile_derive_user_profile_key` (mobile only).
  - Rust FFI provides `rn_keys_node_install_profile_public_key`, `rn_keys_node_get_profile_public_key_by_label`, and `rn_keys_node_decrypt_with_profile` (node only).

## Concrete Types

Two concrete, role-specific managers. Each creates and owns its FFI handle and implements `CommonKeyManager` plus its role protocol. Both are actors.

```swift
public actor NodeKeyManager: NodeOnly { /* FFI-backed */ }
public actor MobileKeyManager: MobileOnly { /* FFI-backed */ }
```

Initialization:
- `NodeKeyManager` initializes the FFI handle then calls `rn_keys_init_as_node`.
- `MobileKeyManager` initializes the FFI handle then calls `rn_keys_init_as_mobile`.

No type exposes APIs from the opposite role, so misuse is prevented at compile-time.

## Swift 6 FFI Concurrency Guidance

This section defines mandatory rules for calling C/Rust FFI from actor methods under Swift 6 strict concurrency.

1) No suspension during FFI pointer usage
- Actor methods may be `async` but must not call `await` between:
  - preparing arguments and pointers
  - invoking `rn_*` functions
  - copying and freeing outputs
- All FFI work happens in a single synchronous region.

2) Never capture `self` in FFI closures
- Copy the handle at method start: `let handle = self.handle`.
- Pass only local variables into closures for `withRnErrorCode` and `withUnsafeBytes`.
- Do not reference `self` inside non-escaping closures used for FFI.

3) Use nonisolated FFI helper functions
- Implement internal `nonisolated` free/static functions (or top-level funcs) like:
  - `func ffi_encrypt_with_envelope(_ handle: UnsafeMutableRawPointer, ...) throws -> Data`
- These helpers perform the `rn_*` call inside `withRnErrorCode`, copy results to `Data`, and free via `rn_free`/`rn_string_free`.
- Actor methods obtain locals, then call helpers. This avoids capturing actor state in closures and keeps concurrency annotations simple.

4) Only pass stack-local pointers to FFI
- Allocate `var outPtr`, `var outLen` as locals, pass them to FFI once, and immediately copy-and-free results.
- For inputs, use `withUnsafeBytes` with non-escaping closure and ensure the call occurs inside the closure.
- Never store or return raw pointers; only return Swift `Data`/`String`.

5) Enforce one-handle-per-actor and no sharing
- The FFI handle is owned by the actor. Do not share it across actors or threads.
- If a raw handle must be exposed to other wrappers (e.g., transport), pass it transiently in the same synchronous call path.

6) No @unchecked Sendable anywhere
- Protocols should not require `Sendable`.
- Actors provide isolation; do not mark actor state as Sendable.

7) Logging and error translation
- No `print()` in production. Use the shared logger (`RunarLogger`) if logging is needed around FFI calls.
- Translate `RnError` to `FFIError` synchronously; do not suspend while accessing error message pointers; free message strings immediately.

8) Validation boundaries
- Validate Swift inputs before FFI call (non-empty, size limits, string lengths) to avoid undefined behavior inside Rust.
- Do not call FFI with null/fake handles. If testing invalid-handle paths is required, add Swift-side guards to throw deterministically.

9) Do not return non-Sendable classes across actor boundaries
- Never return a reference type (e.g., `CAClient`) from an actor-isolated method to a nonisolated context.
- If an actor needs to create a wrapper object, return a raw handle (`UnsafeMutableRawPointer`) or a value type, and construct the class on the caller side.
- Alternatively, execute the FFI creation in a `nonisolated` helper and keep object construction in the same isolation domain.

10) CA wrappers concurrency model
- `CANode`, `CAServer`, `SharedCANode` are plain classes (not actors, not `@MainActor`). All their instance methods that touch FFI are `nonisolated` and follow rules 1–4.
- `CAClient` is an ACTOR to enable actor-to-actor factory construction from `NodeKeyManager` and avoid returning non-Sendable across isolation.

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
- Async APIs surface errors via `throws`; cancellation is cooperative (FFI calls are synchronous; cancellation boundaries are at call sites).

## Serializer Integration

- Serializer depends only on `CommonKeyManager` and uses `await` for all calls.
- Profile install/get APIs are node-only and must not be referenced by serializer or mobile code.
- Node-only `decryptWithProfile` remains in `NodeOnly`; any use must live in node-aware code.

Example usage:
```swift
let km: CommonKeyManager = NodeKeyManager()
let eed = try await km.encryptWithEnvelope(data: payload, networkPublicKey: netKey, profilePublicKeys: [pk1, pk2])
let plain = try await km.decryptEnvelope(envelopeData: eed)
```

## Refactor Plan (swift-ffi)

1. Add protocols: `CommonKeyManager`, `NodeOnly`, `MobileOnly` with `async throws` APIs.
2. Implement `public actor NodeKeyManager` and `public actor MobileKeyManager`:
   - Own FFI handle lifecycle (`rn_keys_new`/`rn_keys_free`), init as node/mobile.
   - Implement common and role-specific methods; all FFI calls executed within actor context.
   - Follow the Swift 6 FFI Concurrency Guidance for all methods and helpers.
3. Remove `KeysHandle` entirely. Replace all usages with role-specific actors or `CommonKeyManager` where appropriate.
4. Unify method names: remove `mobile*` prefixes. Provide only the common names on respective actors.
5. Update transport/discovery and other helpers to accept the appropriate role-specific actor or `CommonKeyManager`.
6. Update serializer to depend only on `CommonKeyManager` and use `await` for all calls.
7. Update all tests to `async` variants using `await` and `XCTExpectFailure` only when justified; no skips.
8. Run SwiftLint/SwiftFormat and fix violations.

## Test Strategy

- Convert test suites to async tests (XCTest supports async/await):
  - Message crypto tests: concurrent scenarios via `async let`/Task groups; ensure deterministic results.
  - Symmetric keys/persistence: remove assumptions about per-name encryption; validate default-key behavior.
  - Profile keys: ensure install/get are used only with node actor; mobile tests only derive.
  - Network encryption: implement full network key exchange flow (mobile generates message → node installs → encrypt/decrypt network data).
  - Transport behavior: perform CA enrollment/renewal setup via FFI before starting transport; remove skips.
- Cross-check coverage with Rust tests for equivalent flows and vectors.

## Security and Determinism

- Strict pointer and memory management (use `defer` frees for FFI outputs) within actor context.
- No hidden behavior or role fallbacks.
- Deterministic error propagation; no debug prints in production error paths.


Lessons Learned during implementation:
### Lessons learned: Swift 6-safe FFI without @unchecked

- **Actor isolation at the right boundary**: `NodeKeyManager`/`MobileKeyManager` as actors; all public APIs are `async throws`. The CA wrappers (`CANode`, `CAServer`, `SharedCANode`) are plain classes (not actors) with nonisolated FFI methods. `CAClient` is an actor (so returning it across actor boundaries is Sendable).

- **Synchronous FFI regions only**:
  - Copy the handle at method start: `let handle = self.handle`.
  - Do not suspend inside the FFI-critical section.
  - Use stack-local `outPtr/outLen`; copy to `Data` immediately; always free via `rn_free`/`rn_string_free` in the same scope.
  - Use `withUnsafeBytes` closures only to immediately invoke the FFI call.

- **Nonisolated FFI helpers**:
  - Internal `nonisolated` helpers perform the entire `rn_*` call + copy + free. Actor methods prepare arguments and call the helper with locals, never capturing `self`.

- **No non-Sendable across actors**:
  - Do not return `UnsafeMutableRawPointer` or class instances from actor methods. Return value types or actor references (e.g., return `CAClient` actor). Construct non-actor objects in the same isolation domain where their raw handle is created.

- **No `@unchecked Sendable` anywhere**:
  - Actor isolation and strict FFI discipline remove the need for `@unchecked`. We rely on Sendable actor references and thread safety guaranteed by synchronous FFI sections.

- **Deterministic error propagation**:
  - The standard pattern: `withRnErrorCode { rn_call(..., errPtr) }` → check code/error → throw `FFIError` with immediate string copy/free.

- **Memory hygiene**:
  - Always free FFI-owned buffers/strings.
  - Never persist FFI pointers beyond the call; convert to Swift types immediately.

- **CBOR parity and schema discipline**:
  - Ensure DER/CBOR fields match Rust one-for-one. Extract `csr_der` from `SetupToken` CBOR before requests. Encode arrays (e.g., admin SKIs) as actual CBOR arrays.

- **Temporal stability after state changes**:
  - Insert very small sleeps (e.g., 50ms) after certificate installation before issuing a new CSR/renewal. This mirrors Rust’s natural timing (thread scheduling/blocking) and avoids racing with background teardown/upkeep in transport/keystore layers.

### What went wrong in the first attempt (and why we changed back to classes)

- **Made CA wrappers actors/@MainActor**:
  - Returning non-Sendable (raw pointers or non-actor classes) across actor isolation triggered Swift 6 “sending risks data race” diagnostics and, in practice, runtime crashes (signal 11) under load.
  - Some tests used main-actor assertions; mixing `@MainActor` with cross-actor non-Sendable references caused isolation violations.

- **Corrective changes**:
  - Reverted `CANode`, `CAServer`, `SharedCANode` to plain classes with nonisolated FFI methods. This eliminated cross-actor Sendable requirements for their raw handles.
  - Made `CAClient` an actor and created it via an actor-safe factory pattern (or local nonisolated helper + construction in the same isolation), so we only ever pass an actor reference (Sendable by construction).
  - Ensured no FFI raw pointer or non-Sendable class crosses actor boundaries.

### Other concrete pitfalls we fixed (to avoid repeating)

- **Network ID mismatch**: use `test_network` consistently (not `test-network`) across client/server/token.
- **CSR encoding**: for enroll/renew, send raw DER from `SetupToken`’s `csr_der` (decode first). Sending the whole `SetupToken` as CSR causes parse/tag errors and wrong message types (0x2000).
- **Admin SKIs format**: CBOR array of strings, not a bare string.
- **Correct installer**: install node certificates on `NodeKeyManager`, not on `MobileKeyManager`.
- **Vector parity**: FFI CBOR vectors must match Rust exactly (lengths, fill bytes, timestamps).
- **Logging vs prints**: prefer the shared logger; never keep `print` in production paths.

### Quick checklist for future FFI work

- **Before coding**:
  - Decide: actor vs class. Actors only for high-level safe surfaces; wrappers holding raw handles are plain classes with nonisolated methods.
  - Define FFI helpers as nonisolated functions.

- **While coding**:
  - Copy handle to a local; no suspension during FFI; immediate copy+free.
  - Never return raw pointers/classes across actors; return value types or actor refs.
  - Validate inputs; propagate FFI error codes/messages deterministically.

- **After coding**:
  - Cross-check Rust tests for data shapes and flow.
  - Add tiny sleeps after cert install if issuing subsequent CSR/renew; only where state transitions occur.

- **Tests**:
  - Use real flows only (no stubs): real CA setup, real enroll/renew, real transport.
  - Ensure network_id and CBOR schemas match Rust exactly.

This is now documented in the design and reflected in code. I can apply the two test fixes (edge-cases error semantics and multi-certificate installation) if you want me to proceed.
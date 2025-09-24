# Swift Serializer & Macros — Current State, Parity Assessment, and Implementation Plan

## Executive Summary

- The core serialization infrastructure is solid (AnyValue, CBOR, containers) and aligns with Rust.
- A unified `SerializationRegistry` actor exists and is the single source of truth, but some integration points in `AnyValue` are still disabled.
- Field-level encryption parity is blocked by an incomplete Swift-side label resolution model and missing label-group encryption orchestration. Macros assume capabilities that don’t yet exist at runtime.
- This document consolidates status and defines an actionable, production-ready plan to achieve 100% parity with `runar-serializer` and `runar-serializer-macros`.

## Scope and Alignment

- Swift packages: `swift-serializer`, `swift-serializer-macros`.
- Rust references: `runar-rust/runar-serializer`, `runar-rust/runar-serializer-macros`.
- Crypto via FFI: `swift-ffi` CommonKeyManager protocol (implemented by NodeKeyManager and MobileKeyManager). Swift must present actual public keys to FFI, not labels.

## Current State (Swift)

- AnyValue/ArcValue parity: Complete. Categories, lazy decoding, bytes/json handling consistent with Rust.
- CBOR stack: Uses SwiftCBOR with deterministic encoding in hot paths.
- Registry: `SerializationRegistry` actor implemented with wire-name, encryptor/decryptor/decoder/JSON converter maps and a sync cache for wire-name lookups.
- Envelope encryption utilities: Present and working for envelopes; CBOR (de)serialization helpers provided.
- Keystore integration: Uses CommonKeyManager protocol for encryption/decryption operations. Both NodeKeyManager and MobileKeyManager implement this protocol.
- Macros: Implemented but generate code that relies on resolver/encryption orchestration not yet available at runtime. Registration is currently non-deterministic (fire-and-forget) in some methods.
- Tests: Non-macro tests largely pass; macro-driven encrypted flows are pending due to missing runtime support and async registration guarantees.

## Critical Gaps vs Rust

- Missing Swift-side label resolution model equivalent to Rust's `LabelResolver` with `LabelKeyInfo` (network + multiple profile keys). The FFI does not provide label resolution - it must be implemented in Swift.
- Missing label-group encryption orchestration that takes a grouped sub-struct, serializes to CBOR, resolves keys, and calls keystore to produce an envelope, mirroring Rust’s `encrypt_label_group`.
- Registry integration in `AnyValue` (serialize/deserialize) is partially disabled. Encryption path during serialize must be registry-first with no fallbacks; decode path must dispatch via registry, including decrypt-then-decode for encrypted types when a keystore is provided.
- Macros must generate code consistent with the runtime contracts (async-first registration, correct resolver API usage, grouping, CBOR encode/decode, and registry wiring).

## Design Decisions (Deterministic, No Fallbacks)

- Single path for encryption: When `SerializationContext` is provided, `AnyValue` must use the registry encryptor for the boxed struct value, compute the encrypted wire-name, and set the header `encrypted` flag. If any prerequisite is missing, throw a strict error.
- Single path for decoding: For non-primitive/container wire names, the registry decoder must exist. If the decoder returns an encrypted companion type while the caller expects the plain type and provides a keystore, perform decrypt-then-decode. Otherwise, throw.
- Label resolution: Must deliver actual key material references (network public key and multiple profile public keys as Data) required by CommonKeyManager APIs. No string-only shortcuts.
- Async-first macros: Public macro-generated APIs await deterministic `_ensureRegistered()`; no background registration tasks.

## Actor Isolation and Concurrency Model (Final)

- Decision: Make `AnyValue` non-MainActor for crypto/registry paths. Keep potential UI-only helpers `@MainActor` if truly needed (none exist today in serializer).
- Reason: `AnyValue` is immutable and `Sendable`; crypto and FFI calls must not run on the main thread. Actor-hopping to UI executor is harmful for performance and can deadlock tests.

Detailed API contracts (non-MainActor unless noted):
- AnyValue
  - `public func serialize(context: SerializationContext? = nil) async throws -> Data`
  - `public func asType<T>(keystore: CommonKeyManager? = nil) async throws -> T`
  - `public func asEncrypted<T: RunarEncryptable>(_: T.Type, keystore: CommonKeyManager, resolver: LabelResolver) async throws -> T.Encrypted`
  - `private func deserializeLazyData<T>(_ lazyData: LazyData, to: T.Type, keystore: CommonKeyManager? = nil) async throws -> T`
  - UI-only helpers: none at present. If future helpers touch UI (UIKit/AppKit), they must be declared `@MainActor` explicitly and must not call crypto/registry logic directly.

- SerializationRegistry (actor)
  - Encryptor closure type: `@Sendable (Any, CommonKeyManager, LabelResolver) async throws -> Data`
  - Decryptor closure type: `@Sendable (Data, CommonKeyManager) async throws -> Any`
  - Decoder closure type (plain decode): `@Sendable (Data) throws -> Any`
  - JSON converter closure type: `@Sendable (AnyValue) async throws -> Any` (no `@MainActor`)
  - Lookup methods remain `async` due to actor isolation:
    - `func encryptor(for wireName: String) async -> (@Sendable (Any, CommonKeyManager, LabelResolver) async throws -> Data)?`
    - `func decryptor(for wireName: String) async -> (@Sendable (Data, CommonKeyManager) async throws -> Any)?`
    - `func decoder(for wireName: String) async -> (@Sendable (Data) throws -> Any)?`
    - `func jsonConverter(for wireName: String) async -> (@Sendable (AnyValue) async throws -> Any)?`
    - `func encryptedWireName(for plainWireName: String) async -> String?`

- SerializationContext (value type, `Sendable`)
  - `public struct SerializationContext: Sendable {`
  - `  public let keystore: CommonKeyManager`
  - `  public let resolver: LabelResolver`
  - `}`

- Macros (generated APIs are non-MainActor)
  - `public func toAnyValue() async -> AnyValue` (awaits `Self._ensureRegistered()`)
  - `public func encryptWithKeystore(_ keystore: CommonKeyManager, _ resolver: LabelResolver) async throws -> Encrypted`
  - `public static func fromAnyValue(_ value: AnyValue) async throws -> Self`

- Testing and callers
  - Callers must `await` all async methods; do not rely on sleeps.
  - No code path should force crypto onto the main thread. If a UI boundary is needed, hop to MainActor at the very edge (UI layer), not inside serializer.

### 1) Swift-side Label Resolution Model (Parity)

Implement types and behavior aligning with Rust `traits.rs`:
- `LabelKeyInfo { profilePublicKeys: [Data], networkPublicKey: Data? }` as the canonical output. These are the actual public key bytes FFI expects.
- `LabelResolverConfig`, `LabelValue/LabelKeyword` (if needed for dynamic resolution), and a concrete `LabelResolver` creation path analogous to Rust’s `create_context_label_resolver` using system config + user profile keys from the request context.
- Expose: `func canResolve(_:) -> Bool`, `func resolveLabelInfo(_:) throws -> LabelKeyInfo?`, `func availableLabels() -> [String]`.
- No FFI involvement in label resolution. The resolver is 100% Swift-side and authoritative.
- Validation: each label must specify at least one of `networkPublicKey` or `userKeySpec` (or both). Network-only and profile-only labels are valid; labels with neither are invalid. If a network key is provided, it must be non-empty and of correct length.

Outcome: Deterministic, context-aware, pre-resolved key info for label-group encryption.

### 2) Label-Group Encryption Orchestration

Create `LabelGroupEncryption.swift`:
- `struct EncryptedLabelGroup { let label: String; let envelope: EnvelopeEncryptedData? }`.
- `func encryptLabelGroup<T: Codable>(label: String, fieldsStruct: T, keystore: CommonKeyManager, resolver: LabelResolver) async throws -> EncryptedLabelGroup`:
  - Encode `fieldsStruct` to CBOR using SwiftCBOR Codable encoder with canonical options (stable maps, deterministic ordering).
  - If `resolver.canResolve(label)` is false, return `EncryptedLabelGroup(label, envelope: nil)` (expected partial-access case).
  - Otherwise, `let info = try resolver.resolveLabelInfo(label)` and call `keystore.encryptWithEnvelope(data: plainBytes, networkPublicKey: info.networkPublicKey, profilePublicKeys: info.profilePublicKeys)`.
  - Return `EncryptedLabelGroup(label: label, envelope: envelope)`.
- `func decryptLabelGroup<T: Codable & RunarDefault>(encryptedGroup: EncryptedLabelGroup, keystore: CommonKeyManager) async throws -> T`:
  - If `encryptedGroup.envelope == nil`, return `T.runarDefaultValue`.
  - Else, decrypt with `keystore.decryptEnvelope` (CommonKeyManager) or `keystore.decryptWithProfile` (NodeOnly) per keystore capabilities; then CBOR-decode bytes to `T`.
  - Decrypt errors due to missing keys are contained and result in `T.runarDefaultValue`. Malformed envelopes or CBOR decode errors throw `SerializerError.deserializationFailed`.

Outcome: Exact Rust behavior for per-label field-group processing.

### 3) Re-enable Registry Integration in AnyValue

- Add boxed raw value retrieval to `AnyValueBox` so the registry encryptor can receive the original struct as `Any`.
- Serialization path (registry-first, strict):
  - Header format remains `[category][encrypted][name_len][name][payload]`.
  - When `context == nil`: serialize plain using existing CBOR fast paths.
  - When `context != nil` and category == `.struct`:
    - Lookup encryptor: `await SerializationRegistry.shared.encryptor(for: plainWireName)`; if nil, throw `SerializerError.serializationFailed("Missing encryptor for \(plainWireName)")`.
    - Lookup encrypted wire name: `await SerializationRegistry.shared.encryptedWireName(for: plainWireName)`; if nil, throw `serializationFailed`.
    - Obtain original value from box; if unavailable, throw `serializationFailed("Missing boxed raw value")`.
    - Produce payload: invoke encryptor with `(rawValue, context.keystore, context.resolver)`; set `encrypted = 0x01` and use encrypted wire name in header; append payload bytes.
- Deserialization path (registry-first, strict):
  - For primitives/containers/json/bytes: keep strict wire-name checks as implemented.
  - For custom wire names (structs and encrypted structs):
    - Lookup decoder: `await SerializationRegistry.shared.decoder(for: wireName)`; if missing, throw `Unknown wire name`.
    - If decoder returns plain `T`, wrap into `AnyValue` result appropriately.
    - If decoder returns `AnyRunarDecryptable` and a caller later requests the plain type via `asType<T>(keystore:)`, decrypt with the provided keystore and return `T`. If the caller requests the encrypted type, return as-is.
  - No fallbacks; all missing registrations are hard errors with precise messages.

Outcome: Deterministic registry-first behavior, no silent fallbacks.

### 4) Macro Generation Updates (swift-serializer-macros)

- Make public macro-generated methods async and await `_ensureRegistered()` deterministically:
  - `toAnyValue() async -> AnyValue`
  - `encryptWithKeystore(_: _:) async throws -> Encrypted`
  - `fromAnyValue(_:) async throws -> Self`
- Group fields by label, synthesize sub-structs, and an encrypted companion struct with optional envelopes per label (deterministic label order: system, user, then others lexicographically).
- Register with the unified `SerializationRegistry` only: wire names, decoders for plain/encrypted, and encryptors for plain types targeting the encrypted wire name.

Outcome: Generated code compiles and honors runtime contracts.

### 5) Tests (Real Implementations, No Mocks)

- Use `swift-test-utils` fixtures to construct real NodeKeyManager or MobileKeyManager instances (both implement CommonKeyManager) and a configurable resolver matching Rust semantics.
- Add encryption integration tests:
  - Per-label encryption presence/absence via `canResolve` logic.
  - Node vs Mobile keystores verify partial access semantics.
  - AnyValue serialize(context:) uses registry encryptor and sets encrypted header/wire name.
  - AnyValue deserialization routes via registry and supports decrypt-then-decode when keystore provided.
- Remove sleeps; all macro entry points are awaited.

### 6) Documentation Cleanup

- Archive outdated docs: `improve_async_02.md`, `label_resolver_issues.md`, `use_ffi_keys.md`.
- Keep this file as the single source of truth for status and plan.

## Acceptance Criteria

- Swift label resolution provides deterministic key info consistent with Rust.
- Label-group encryption matches Rust behavior byte-for-byte for CBOR payloads.
- AnyValue uses registry paths for encrypt/decode with strict erroring on missing prerequisites.
- Macros generate compiling, async-first code and register exclusively with `SerializationRegistry`.
- End-to-end tests with real keystores pass without sleeps or fallbacks.
- SwiftLint passes; SwiftFormat applied.

## Next Actions (Ordered)

1. Implement LabelResolver parity types and context creation path in `swift-serializer` (or upgrade FFI protocol and remove adapter when ready).
2. Add `LabelGroupEncryption.swift` with encrypt/decrypt functions.
3. Re-enable and finalize `AnyValue` registry integration and boxed raw value retrieval.
4. Update macros for async-first registration and correct grouping/encryption generation.
5. Add integration tests leveraging `swift-test-utils`; run full test suites.
6. Archive outdated docs; keep this document updated.

### Tests and Usage Notes

- Tests will construct `LabelResolver` manually (no Factory, no context cache). This mirrors Rust test approach.
- Macro-generated entry points must be async and call `await _ensureRegistered()` before use; tests await these methods—no sleeps.
- Add tests for:
  - encrypt/decrypt label groups across system/user/system_only/search labels.
  - AnyValue serialization with context performs registry encryption and sets encrypted header and wire name.
  - AnyValue lazy deserialization dispatches via registry; decrypt-then-decode path succeeds with provided keystore.

### Future (Node-only)

- Factory (Context-Aware Construction) and Caching for `LabelResolver` are deferred until Node work. Do not implement now.

## FFI Integration Guide

### Current FFI API Structure

The `swift-ffi` package provides a unified key management interface through the `CommonKeyManager` protocol:

```swift
public protocol CommonKeyManager {
    // Envelope crypto (serializer-critical)
    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profilePublicKeys: [Data]) async throws -> Data
    func decryptEnvelope(envelopeData: Data) async throws -> Data
    
    // Symmetric key management
    func encryptLocalData(data: Data) async throws -> Data
    func decryptLocalData(encryptedData: Data) async throws -> Data
    
    // General message crypto
    func encryptForNetwork(data: Data, networkPublicKey: Data) async throws -> Data
    func decryptNetworkData(encryptedEnvelope: Data) async throws -> Data
}
```

### Concrete Implementations

- **`NodeKeyManager`**: Implements `CommonKeyManager` + `NodeOnly` protocol
  - Additional methods: `decryptWithProfile(envelopeData:profileId:)`, `deriveUserProfileKey(label:)`, etc.
  - Used for node-side operations with full access to all keys

- **`MobileKeyManager`**: Implements `CommonKeyManager` + `MobileOnly` protocol  
  - Additional methods: `getUserPublicKey()`, `installNetworkPublicKey(_:)`, etc.
  - Used for mobile-side operations with limited access

### Serializer Integration Points

1. **SerializationContext**: Must accept `CommonKeyManager` (not specific implementations)
   ```swift
   public struct SerializationContext {
       public let keystore: CommonKeyManager  // Protocol, not concrete type
       public let resolver: LabelResolver
       public let networkId: String
       public let profilePublicKey: Data?
   }
   ```

2. **EnvelopeCrypto Protocol**: Should be removed - use `CommonKeyManager` directly
   ```swift
   // REMOVE: public protocol EnvelopeCrypto
   // USE: CommonKeyManager directly for encryption/decryption
   ```

3. **LabelGroupEncryption**: Must use `CommonKeyManager` methods
   ```swift
   func encryptLabelGroup<T: Codable>(
       label: String, 
       fieldsStruct: T, 
       keystore: CommonKeyManager,  // Protocol, not concrete type
       resolver: LabelResolver
   ) async throws -> EncryptedLabelGroup
   ```

### Key Design Principles

- **No Label Resolution in FFI**: The FFI does not provide label resolution APIs. All label-to-key mapping must happen in Swift.
- **Pre-resolved Keys Only**: CommonKeyManager expects actual public key bytes (Data), not labels or IDs.
- **Protocol-Based Design**: Use `CommonKeyManager` protocol everywhere, allowing both NodeKeyManager and MobileKeyManager to be used interchangeably.
- **Async-First**: All CommonKeyManager methods are async and must be awaited.

### Migration from Current Implementation

1. **Remove MockEnvelopeCrypto**: Replace with direct `CommonKeyManager` usage
2. **Update SerializationContext**: Change `keystore: EnvelopeCrypto` to `keystore: CommonKeyManager`
3. **Update LabelGroupEncryption**: Use `keystore.encryptWithEnvelope()` directly
4. **Update AnyValue**: Remove envelope-specific types, use raw `Data` for encrypted payloads
5. **Update Tests**: Use real `NodeKeyManager` or `MobileKeyManager` instances from `swift-test-utils`

### Notes on FFI Alignment

- CommonKeyManager exposes only keystore encryption/decryption with public keys (envelope crypto). It does not and will not provide label resolution APIs.
- The Swift-side `LabelResolver` must map labels to actual recipients: `networkPublicKey` and `profilePublicKeys` as raw bytes (Data), pre-resolved before invoking CommonKeyManager.
- Ensure CommonKeyManager is fed with these pre-resolved recipients exactly once per operation; avoid any hidden defaults or fallbacks.
- Both NodeKeyManager and MobileKeyManager implement CommonKeyManager, allowing the serializer to work with either keystore type.

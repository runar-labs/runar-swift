# Swift Serializer & Macros — Current State, Parity Assessment, and Implementation Plan

## Executive Summary

- The core serialization infrastructure is solid (AnyValue, CBOR, containers) and aligns with Rust.
- A unified `SerializationRegistry` actor exists and is the single source of truth, but some integration points in `AnyValue` are still disabled.
- Field-level encryption parity is blocked by an incomplete Swift-side label resolution model and missing label-group encryption orchestration. Macros assume capabilities that don’t yet exist at runtime.
- This document consolidates status and defines an actionable, production-ready plan to achieve 100% parity with `runar-serializer` and `runar-serializer-macros`.

## Scope and Alignment

- Swift packages: `swift-serializer`, `swift-serializer-macros`.
- Rust references: `runar-rust/runar-serializer`, `runar-rust/runar-serializer-macros`.
- Crypto via FFI: `swift-ffi` EnvelopeCrypto (mobile/node keystores). Swift must present actual public keys/IDs to FFI, not labels.

## Current State (Swift)

- AnyValue/ArcValue parity: Complete. Categories, lazy decoding, bytes/json handling consistent with Rust.
- CBOR stack: Uses SwiftCBOR with deterministic encoding in hot paths.
- Registry: `SerializationRegistry` actor implemented with wire-name, encryptor/decryptor/decoder/JSON converter maps and a sync cache for wire-name lookups.
- Envelope encryption utilities: Present and working for envelopes; CBOR (de)serialization helpers provided.
- Macros: Implemented but generate code that relies on resolver/encryption orchestration not yet available at runtime. Registration is currently non-deterministic (fire-and-forget) in some methods.
- Tests: Non-macro tests largely pass; macro-driven encrypted flows are pending due to missing runtime support and async registration guarantees.

## Critical Gaps vs Rust

- Missing Swift-side label resolution model equivalent to Rust’s `LabelResolver` with `LabelKeyInfo` (network + multiple profile keys). Swift currently exposes only label→profileId in several adapters.
- Missing label-group encryption orchestration that takes a grouped sub-struct, serializes to CBOR, resolves keys, and calls keystore to produce an envelope, mirroring Rust’s `encrypt_label_group`.
- Registry integration in `AnyValue` (serialize/deserialize) is partially disabled. Encryption path during serialize must be registry-first with no fallbacks; decode path must dispatch via registry, including decrypt-then-decode for encrypted types when a keystore is provided.
- Macros must generate code consistent with the runtime contracts (async-first registration, correct resolver API usage, grouping, CBOR encode/decode, and registry wiring).

## Design Decisions (Deterministic, No Fallbacks)

- Single path for encryption: When `SerializationContext` is provided, `AnyValue` must use the registry encryptor for the boxed struct value, compute the encrypted wire-name, and set the header `encrypted` flag. If any prerequisite is missing, throw a strict error.
- Single path for decoding: For non-primitive/container wire names, the registry decoder must exist. If the decoder returns an encrypted companion type while the caller expects the plain type and provides a keystore, perform decrypt-then-decode. Otherwise, throw.
- Label resolution: Must deliver actual key material references (network id and multiple profile ids) required by FFI keystore APIs. No string-only shortcuts.
- Async-first macros: Public macro-generated APIs await deterministic `_ensureRegistered()`; no background registration tasks.

## Detailed Plan

### 1) Swift-side Label Resolution Model (Parity)

Implement types and behavior aligning with Rust `traits.rs`:
- `LabelKeyInfo { profilePublicKeys: [Data], networkPublicKey: Data? }` or, if FFI requires IDs, maintain `profileIds: [String], networkId: String?` and ensure the keystore API matches. The key is pre-resolved, deterministic input to crypto.
- `LabelResolverConfig`, `LabelValue/LabelKeyword` (if needed for dynamic resolution), and a concrete `LabelResolver` creation path analogous to Rust’s `create_context_label_resolver` using system config + user profile keys from the request context.
- Expose: `func canResolve(_:) -> Bool`, `func resolveLabelInfo(_:) throws -> LabelKeyInfo?`, `func availableLabels() -> [String]`.
- Integration: Provide an adapter layer only if the FFI protocol is not yet upgraded. Preferred long-term: upgrade FFI protocol to match parity.

Outcome: Deterministic, context-aware, pre-resolved key info for label-group encryption.

### 2) Label-Group Encryption Orchestration

Create `LabelGroupEncryption.swift`:
- `struct EncryptedLabelGroup { let label: String; let envelope: EnvelopeEncryptedData? }`.
- `func encryptLabelGroup<T: Codable>(label: String, fieldsStruct: T, keystore: EnvelopeCrypto, resolver: LabelResolver) throws -> EncryptedLabelGroup`:
  - Encode `fieldsStruct` to CBOR deterministically.
  - Resolve label via resolver; if absent, return `EncryptedLabelGroup(label, envelope: nil)` (expected partial access).
  - Encrypt via keystore using network and profile recipients from `LabelKeyInfo`.
- `func decryptLabelGroup<T: Codable & RunarDefault>(encryptedGroup: EncryptedLabelGroup, keystore: EnvelopeCrypto) throws -> T`:
  - If envelope is nil, return `T.runarDefaultValue` (expected partial access semantics).
  - Decrypt envelope and CBOR-decode to T.

Outcome: Exact Rust behavior for per-label field-group processing.

### 3) Re-enable Registry Integration in AnyValue

- Add boxed raw value retrieval to `AnyValueBox` so the registry encryptor can receive the original struct as `Any`.
- In `AnyValue.serialize(context:)`:
  - Require registry encryptor when `context != nil` for struct/plain types; compute encrypted wire name; set header encrypted bit; append encryptor-produced payload.
  - If missing encryptor or mapping, throw `serializationFailed`.
- In lazy deserialization default branch:
  - Lookup decoder via registry and dispatch.
  - If decoder returns an encrypted companion type and caller expects plain T with a keystore, decrypt and return.
  - Otherwise, throw on unknown wire name.

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

- Use `swift-test-utils` fixtures to construct real keystores and a configurable resolver matching Rust semantics.
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

## Notes on FFI Alignment

- Preferred: enhance `RunarFFI.LabelResolver` to expose `canResolve(_:)` and return `LabelKeyInfo` rather than a single string. If not immediately possible, provide a temporary adapter in `swift-serializer` that constructs `LabelKeyInfo` from available FFI calls and configuration, with strict behavior (no silent defaults).
- Ensure EnvelopeCrypto APIs accept the resolved recipients exactly once per operation; avoid hidden fallbacks.

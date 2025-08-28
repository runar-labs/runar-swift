## 🔧 **IMPLEMENTATION PLAN**

### **Phase 1: Create Test Infrastructure** ✅ **COMPLETED**
1. **Create `TestKeystoreFactory.swift`** in swift-test-utils ✅
   - `createMobileKeystore()` - Creates and initializes mobile keystore ✅
   - `createNodeKeystore()` - Creates and initializes node keystore ✅
   - `createTestContext()` - Creates complete test context with resolver ✅

2. **Create `ConfigurableLabelResolver.swift`** in swift-test-utils ✅
   - Mirror Rust's `ConfigurableLabelResolver` implementation ✅
   - Support for profile IDs and network IDs ✅
   - Configurable label mappings ✅

3. **Create `KeyMappingConfig.swift`** in swift-test-utils ✅
   - Mirror Rust's `KeyMappingConfig` structure ✅
   - Support for label-to-key mappings ✅

### **Phase 2: Create Encryption Tests** 🚧 **IN PROGRESS**
1. **Create `EncryptionIntegrationTests.swift`** in serializer tests
   - Basic encryption/decryption flow
   - Macro-generated type testing
   - Access control validation

2. **Create `MacroEncryptionTests.swift`** in serializer tests
   - Test @Encrypted macro integration
   - Test @Plain macro integration
   - Test label resolution

3. **Create `EndToEndEncryptionTests.swift`** in serializer tests
   - Complete encryption/decryption round-trip
   - Multiple keystore scenarios
   - Real-world access patterns

### **Phase 3: Integration Testing** ⏳ **PENDING**
1. **Test SerializationRegistry Integration**
   - Verify encryptors/decryptors are properly registered
   - Test wire name resolution
   - Test type mapping

2. **Test AnyValue Integration**
   - Verify encryption context handling
   - Test serialization/deserialization
   - Test type conversion

3. **Test Macro Integration**
   - Verify generated code works with registry
   - Test encryption/decryption methods
   - Test protocol conformance

## 📋 **FILES TO CREATE/MODIFY**

### **New Files to Create**
1. `swift-serializer/Tests/RunarSerializerTests/EncryptionIntegrationTests.swift` ⏳ **PENDING**
2. `swift-serializer/Tests/RunarSerializerTests/MacroEncryptionTests.swift` ⏳ **PENDING**
3. `swift-serializer/Tests/RunarSerializerTests/EndToEndEncryptionTests.swift` ⏳ **PENDING**

### **Files Already Created** ✅
1. `swift-test-utils/Sources/RunarTestUtils/KeysAndTransportFixtures.swift` ✅
   - Contains `TestKeystoreFactory` ✅
   - Contains `ConfigurableLabelResolver` ✅
   - Contains `KeyMappingConfig` ✅
   - Contains `TestContext` type alias ✅

### **Files to Modify**
1. **None** - Serializer package should remain unchanged
2. **None** - FFI package should remain unchanged
3. **None** - Macro package should remain unchanged

### **Files to Remove**
1. **None** - All existing code should be preserved

## 🎯 **CURRENT STATUS**

### **✅ COMPLETED**
- **Test Infrastructure**: Created in `swift-test-utils` package
- **Keystore Factory**: `TestKeystoreFactory.createTestContext()` mirrors Rust's `build_test_context()`
- **Label Resolver**: `ConfigurableLabelResolver` with proper label mappings
- **Key Mapping**: `KeyMappingConfig` supporting profile and network keys
- **Build Success**: All fixtures compile and build successfully

### **🚧 NEXT STEPS**
1. **Add swift-test-utils dependency** to serializer package
2. **Create encryption tests** using the test fixtures
3. **Test real encryption/decryption** with FFI keystores
4. **Validate macro integration** with encryption

## 📝 **IMMEDIATE NEXT ACTIONS**

1. **Update serializer package dependencies** to include `swift-test-utils`
2. **Create first encryption test** using `TestKeystoreFactory.createTestContext()`
3. **Test basic encryption flow** with real keystores
4. **Validate the integration** works end-to-end

---

## 🧭 Root Cause Analysis & Detailed Design (Serializer Macros + FFI Keys)

### Executive Summary
- **Problem**: Macro-generated registration is non-deterministic (fire-and-forget). Deserialization rejects unknown wire names because the `SerializationRegistry` paths in `AnyValue` are disabled. Encryption during serialization is also disabled (temporary fallback), so no end-to-end encrypted flow is possible.
- **Outcome**: "Unknown wire name" errors for macro types like `TestProfile`, `SimpleData` and flaky/racy tests that insert sleeps to paper over registration races.
- **Fix Strategy**: Make registration deterministic by using async APIs in macros, re-enable registry usage in `AnyValue` (both serialization and deserialization), eliminate fallbacks, and integrate the real FFI encrypt/decrypt path.

---

### Root Causes
- **RC1 — Fire-and-forget registration in macros**
  - Current code in both `@Plain` and `@Encrypted` macros:
    ```swift
    public func toAnyValue() -> RunarSerializer.AnyValue {
        Task { await Self._ensureRegistered() }
        return RunarSerializer.AnyValue.struct(self)
    }
    ```
  - This creates a background task, returning before registration completes. Callers immediately attempt serialization/deserialization and hit: Unknown wire name.

- **RC2 — Registry paths disabled in `AnyValue`**
  - In `AnyValue.serialize(context:)` and `AnyValue.deserialize(...)`, all `SerializationRegistry` usage is commented out and replaced with temporary fallbacks. As a result:
    - Encryption is not performed via registered encryptors.
    - Deserialization cannot dispatch to registered decoders and throws on unknown wire names for structs.

- **RC3 — No access to original value in `AnyValue` for encryption**
  - `AnyValueBox` stores closures but not a way to retrieve the boxed value as `Any` for registry encryptors. Without the original value, we cannot invoke the encryptor closure (`(Any, EnvelopeCrypto, LabelResolver) -> Data`).

- **RC4 — Tests rely on sleeps and non-existent registry diagnostics**
  - Some tests use `Task.sleep` after `toAnyValue()` to wait for registration and call registry properties that do not exist. This is brittle and will fail as APIs evolve.

---

### Detailed Design Changes

- **D1 — Make macro-generated APIs deterministic (async)**
  - Change macro-generated signatures:
    - `toAnyValue()` → `public func toAnyValue() async -> AnyValue` and `await Self._ensureRegistered()` within.
    - `encryptWithKeystore(_:_: )` → `public func encryptWithKeystore(_ keystore: EnvelopeCrypto, _ resolver: LabelResolver) async throws -> Encrypted` and `await Self._ensureRegistered()` within.
    - Keep `fromAnyValue(_:) async throws` and ensure it `await`s registration.
  - Notes:
    - Macros do not add `PlainSerializable` conformance, so changing method async-ness does not conflict with protocol defaults.
    - Call sites (tests and clients) must `await` these methods. No sleeps, no races.

- **D2 — Re-enable registry-based encryption during serialization**
  - In `AnyValue.serialize(context:)`:
    - If `context == nil`: serialize plain using existing path.
    - If `context != nil`: enforce strict encryption path (no fallbacks):
      - Look up encryptor: `SerializationRegistry.shared.encryptor(for: plainWireName)` where `plainWireName` is the boxed type name (usually the Swift type name).
      - Retrieve the original boxed value (see D3) and call encryptor with `context.keystore` and `context.resolver`.
      - Resolve encrypted header wire name: `SerializationRegistry.shared.encryptedWireName(for: plainWireName)` (must exist) and set header `isEncrypted = 0x01` and `typeName = encryptedWireName`.
      - Append encrypted payload bytes.
    - If no encryptor or no encrypted wire name mapping exists, throw `SerializerError.serializationFailed` (no fallbacks).

- **D3 — Add value retrieval to `AnyValueBox`**
  - Extend `AnyValueBox` with:
    - `private let getValueFn: @Sendable () -> Any?`
    - A method `func rawValue() -> Any? { getValueFn() }`
  - Implement `getValueFn` in `AnyValue.struct(_:)` to return the original value; for other categories it can return `nil`.
  - `AnyValue.serialize(context:)` uses `box.rawValue()` to pass the original value into the encryptor. If `nil`, throw strict error.

- **D4 — Re-enable registry-based decoding for structs and encrypted structs**
  - In `AnyValue.deserialize(_:, keystore:)` + `deserializeLazyData`:
    - When encountering a non-primitive/container name (default branch), look up a decoder from `SerializationRegistry.shared.decoder(for: wireName)`.
    - If found, attempt decode. Two cases:
      - Decoder returns plain `Self` (for a plain wire name): produce the plain value.
      - Decoder returns an encrypted struct (for `Encrypted_<wire>`): produce `AnyRunarDecryptable` value.
    - In `asType<T>()` when a decoder returns `AnyRunarDecryptable` and the caller asks for the plain type `T`, and we have a keystore available, decrypt and return the plain value. If the caller asks for the encrypted type, return it directly.
    - If no decoder exists, throw `Unknown wire name` (strict).

- **D5 — Keep macro registrations comprehensive**
  - `EncryptedMacro` already registers:
    - Encryptors under both the custom wire name and the Swift type name.
    - Decoders under both plain wire name and Swift type name.
    - Decoder for the encrypted wire name.
  - Preserve this, but switch all macro call sites to `await Self._ensureRegistered()`.

- **D6 — Tests and examples**
  - Update tests to use the async API:
    - Replace `let any = x.toAnyValue()` with `let any = await x.toAnyValue()`.
    - Remove sleeps; registration happens synchronously within the awaited call.
  - Avoid using non-existent `SerializationRegistry` diagnostics in tests. Use available introspection APIs (`allWireNames()`, `isRegistered(wireName:)`). If additional diagnostics are needed, add explicit actor methods rather than exposing internal dictionaries.

- **D7 — Security and correctness**
  - Remove all serialization fallbacks that silently proceed without encryption when `context` is present.
  - Fail early with precise error messages when registry entries are missing.
  - Maintain deterministic behavior: single code path guarded by strict preconditions.

---

### File-by-File Change Plan

- **swift-serializer-macros/Sources/RunarSerializerMacrosMacros/PlainMacro.swift**
  - Change generated `toAnyValue()` to `async` and await `_ensureRegistered()`.
  - Ensure `fromAnyValue(_:)` awaits `_ensureRegistered()` (already does).

- **swift-serializer-macros/Sources/RunarSerializerMacrosMacros/EncryptedMacro.swift**
  - Change generated `toAnyValue()` to `async` with `await _ensureRegistered()`.
  - Change `encryptWithKeystore(_:_: )` to `async throws` with `await _ensureRegistered()`.
  - Keep comprehensive registration in `_ensureRegistered()`.

- **swift-serializer/Sources/RunarSerializer/AnyValue.swift**
  - Add `getValueFn`/`rawValue()` to `AnyValueBox`.
  - In `AnyValue.struct(_:)`, set `getValueFn` to return the boxed value.
  - Re-enable `SerializationRegistry` usage in `serialize(context:)`:
    - Enforce encryptor presence and use; compute encrypted header wire name.
  - Re-enable `SerializationRegistry` usage in `deserializeLazyData` default branch:
    - Use registry decoders; if encrypted decoder returns `AnyRunarDecryptable` and a keystore is provided, decrypt on demand when the caller requests the plain type.

- **swift-serializer/Sources/RunarSerializer/SerializationRegistry.swift**
  - No API breaks required. Optionally add explicit diagnostics APIs if needed by tests:
    - `public func allWireNames() -> [String]` (already present)
    - `public func isRegistered(wireName:) -> Bool` (already present)

- **swift-serializer/Tests/**
  - Update tests to use async `toAnyValue()` and `encryptWithKeystore`.
  - Remove sleeps and adjust any debug inspection to existing registry APIs.

---

### Acceptance Criteria
- No "Unknown wire name" errors for macro-decorated structs in tests.
- Encryption path uses real FFI keystore via registry encryptors; no fallbacks.
- Deserialization can decode both plain and encrypted structs via registry.
- All serializer tests pass; macro tests updated for async methods.
- SwiftLint and SwiftFormat pass on modified files.

---

### Validation Plan
- Run unit and integration tests in `swift-serializer` and `swift-serializer-macros`.
- Add an end-to-end test that:
  - Creates real FFI keystores via `TestKeystoreFactory.createTestContext()`.
  - Uses `@Encrypted` struct, `await toAnyValue()`, `serialize(context:)`.
  - `AnyValue.deserialize(..., keystore:)` then `asType<Plain>()` and `asType<Encrypted>()` both succeed.
- Verify no sleeps or timing hacks are needed anywhere.

---

### Risks and Mitigations
- **API change (async)**: Requires updating call sites. Mitigated by localizing changes to test targets now and documenting for downstream users.
- **Actor isolation**: All registry interactions remain actor-isolated; we only call them from async contexts.
- **Performance**: Registration is idempotent and cheap; async boundary is acceptable for serialization entry points.

---

### Next Steps
1. Implement macro async changes (Plain/Encrypted).
2. Implement `AnyValueBox` value retrieval and re-enable registry encrypt/decode paths.
3. Update tests to async usage; remove sleeps and non-existent diagnostics.
4. Run SwiftFormat and SwiftLint on modified modules.
5. Execute full test suite and iterate until green.


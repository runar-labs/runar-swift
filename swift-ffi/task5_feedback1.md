
- I reviewed the implemented managers, protocols, and tests against the design and Rust FFI. I focused on thread-safety/@unchecked Sendable, API alignment, memory safety, and test coverage vs. Rust features.

### Key findings and required fixes

- Thread-safety and @unchecked Sendable
  - NodeKeyManager/MobileKeyManager are declared with @unchecked Sendable but have no internal synchronization and the API is synchronous; tests invoke methods concurrently on the same instance.
```1336:1341:/Users/rafael/dev/runar-swift/swift-ffi/Sources/SwiftFFI/SwiftFFI.swift
public final class NodeKeyManager: @unchecked Sendable, NodeOnly, CommonKeyManager {
    /// The underlying Rust FFI handle
    let handle: UnsafeMutableRawPointer
```
```1924:1930:/Users/rafael/dev/runar-swift/swift-ffi/Sources/SwiftFFI/SwiftFFI.swift
public final class MobileKeyManager: @unchecked Sendable, MobileOnly, CommonKeyManager {
    /// The underlying Rust FFI handle
    private let handle: UnsafeMutableRawPointer
```
  - Tests perform concurrent operations on a single instance, which is unsafe without serialization.
```212:232:/Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/SymmetricKeyTests.swift
for i in 0..<10 {
    group.enter()
    operationQueue.async {
        do {
            let data = testData + Data("\(i)".utf8)
            let encrypted = try self.keysHandle.encryptLocalData(data: data, keyName: keyName)
            let decrypted = try self.keysHandle.decryptLocalData(encryptedData: encrypted, keyName: keyName)
            XCTAssertEqual(decrypted, data, "Concurrent operation \(i) should work correctly")
            ...
```
  - Recommendation (pick one, remove @unchecked):
    - Option A (pragmatic): Remove Sendable from all related protocols; add a private serial DispatchQueue to each manager and run all FFI calls through queue.sync to ensure thread safety. No public API changes. (NOT A GOOD OPTION - discarded)

    - Option B (more modern): Convert managers to actors and make calls async; update call sites/tests to use await. This fully eliminates the need for @unchecked and is safest long-term. 
    DO OPTION B - the proper solutions for long term

- CommonKeyManager vs tests misalignments
  - encryptLocalData/decryptLocalData ignore keyName because the FFI has no name parameter; tests currently assume key selection by name and different ciphertexts per key.
```1717:1746:/Users/rafael/dev/runar-swift/swift-ffi/Sources/SwiftFFI/SwiftFFI.swift
public func encryptLocalData(data: Data, keyName: String) throws -> Data {
    ...
    rn_keys_encrypt_local_data(handle, dataRaw..., &outPtr, &outLen, errPtr)
}
...
public func decryptLocalData(encryptedData: Data, keyName: String) throws -> Data {
    ...
    rn_keys_decrypt_local_data(handle, dataRaw..., &outPtr, &outLen, errPtr)
}
```
    - Fix: Remove keyName parameter from both methods and tests, or document clearly that keyName is not supported and adjust tests to not rely on different keys for encryption. Based on FFI, the correct fix is to remove keyName and test single-default symmetric key behavior.

- getProfilePublicKey return type mismatch with tests
  - Implementation returns (Data, Bool) and uses empty Data for not-found; tests expect (Data?, Bool) with nil when not found.
```1564:1582:/Users/rafael/dev/runar-swift/swift-ffi/Sources/SwiftFFI/SwiftFFI.swift
public func getProfilePublicKey(label: String) throws -> (publicKey: Data, exists: Bool) {
    ...
    if hasKey == 0 {
        return (Data(), false)
    }
```
```175:183:/Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/ProfileKeyTests.swift
let (retrievedKey, exists) = try nodeKeys.getProfilePublicKey(label: label)
XCTAssertFalse(exists, ...)
XCTAssertNil(retrievedKey, ...)
```
    - Fix: Change signature to return (Data?, Bool) and return (nil, false) when hasKey == 0. Update all call sites accordingly (several assertions in ProfileKeyTests already expect Optional).

- Mobile encryptForPublicKey behavior vs tests
  - CommonKeyManager exposes encryptForPublicKey; FFI function `rn_keys_encrypt_for_public_key` is role-agnostic. Tests assert mobile cannot call it and expect an error.
```1819:1837:/Users/rafael/dev/runar-swift/swift-ffi/Sources/SwiftFFI/SwiftFFI.swift
public func encryptForPublicKey(data: Data, publicKey: Data) throws -> Data { ... }
```
```140:148:/Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/MessageCryptoInteropTests.swift
do {
    _ = try mobileKeys.encryptForPublicKey(...)
    XCTFail("Mobile keys should not be able to encrypt for public key")
} catch {
    XCTAssertTrue(error is FFIError)
}
```
    - Fix: Tests should allow both roles to use encryptForPublicKey (per design and FFI). Update tests to remove the expected-error for mobile.

NO TESTS SHUOLOD BE SKIPED.. ALL TESTS MUST ALIGNE with rust 100% and all MUST run properly.. issue smust be fixed and not skipped

- Network encryption tests are skipped
  - Two tests remain skipped due to “complex setup”, which violates the “no skipped tests” policy.
```153:163:/Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/MessageCryptoInteropTests.swift
throw XCTSkip("Network encryption requires complex key setup and installation")
```
    - Fix: Implement the full flow in tests:
      1) Node: try nodeKeys.generateKeys()
      2) Mobile: generateNetworkDataKey(), get nodeAgreementPublicKey from node, createNetworkKeyMessage(...)
      3) Node: installNetworkKey(message)
      4) Use encryptForNetwork (node) and decryptNetworkData (node) or envelope-based network tests as applicable
      5) Assert round-trip. Remove skips.

- Transport tests still skipped due to missing certificate setup
```58:59:/Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/TransportBehaviourTests.swift
XCTSkip("Transport tests require certificate setup - skipping for now")
```
  - Fix: Use CA Node/Client FFI to enroll:
    - Create CA Node via rn_keys_ca_node_... APIs, generate enrollment token, node generate CSR, mobile process setup token, node install certificate, then start transport and run behavior tests. Remove skip.

- Serializer still references KeysHandle
  - The serializer still depends on KeysHandle instead of CommonKeyManager.
```1:74:/Users/rafael/dev/runar-swift/swift-serializer/Sources/RunarSerializer/EnvelopeCrypto.swift
private let keysHandle: KeysHandle
...
try keysHandle.encryptWithEnvelope(...)
```
  - Fix: Replace with CommonKeyManager and call the unified methods. Remove any mobile/node-specific branching in serializer.

- Debug prints in error handling
  - buildError prints debug logs on every error; production should avoid this.
```436:442:/Users/rafael/dev/runar-swift/swift-ffi/Sources/SwiftFFI/SwiftFFI.swift
print("DEBUG: buildError called with code=...")
...
print("DEBUG: Error message: \(message)")
```
  - Fix: Remove prints or behind a controlled logger; avoid side effects during error translation.

DO NOT EVER USE PRINT() for logs.. use the proper logger from /Users/rafael/dev/runar-swift/swift-common/Sources/SwiftCommon/Logger.swift
Check existing code taht uses this logger to underand its patter of use (creating, setting log level and etc). 
Use proper log levels info, debug and trace. follow our standards for this /Users/rafael/dev/runar-swift/.cursor/rules/code-standards.mdc

- Memory safety and FFI pointer management
  - All out buffers and strings are freed via rn_free / rn_string_free using copy helpers. This looks correct.
```468:475:/Users/rafael/dev/runar-swift/swift-ffi/Sources/SwiftFFI/SwiftFFI.swift
private func copyBytesAndFree(...)
    rn_free(pointer, length)
```
```478:483:/Users/rafael/dev/runar-swift/swift-ffi/Sources/SwiftFFI/SwiftFFI.swift
private func copyCStringAndFree(...)
    rn_string_free(pointer)
```
  - For envelope encryption pointer arrays, the C call executes within the lifetime of the withUnsafe closures, so no escaping occurs. Good.

- API/design conformance vs. Rust FFI
  - Methods called map 1:1 to header functions; coverage includes:
    - Envelope encryption/decryption (node/mobile)
    - Symmetric keys, persistence, keystore, general message crypto
    - Node profile/network/cert APIs
    - Mobile setup, network messaging, message crypto
  - No missing FFI coverage identified beyond network test setup and the getProfilePublicKey return semantics.

### Concrete recommendations

- Eliminate @unchecked Sendable and enforce thread safety
  - Preferred: Convert NodeKeyManager/MobileKeyManager to actors and make APIs async. Update tests to await. Zero unsafe annotations.
  - If staying sync: Remove Sendable from protocols and classes; add a private serial DispatchQueue per manager and perform all calls via queue.sync. Update the doc to reflect non-Sendable API and internal serialization.

- Fix API mismatches
  - Change getProfilePublicKey to return (Data?, Bool); return (nil, false) when not found.
  - Remove keyName from encryptLocalData/decryptLocalData (or clearly document it’s ignored) and update tests to reflect single-default symmetric key behavior.

- Update tests
  - Remove all XCTSkip; implement full network-keys flow; implement transport certificate enrollment flow; update mobile encryptForPublicKey test to expect success.
  - Review performance/concurrency tests to ensure they use separate instances or rely on internal serialization (post-fix).

- Clean error handling
  - Remove debug prints from buildError; rely on FFILogger log level if needed.

- Update serializer
  - Swap KeysHandle for CommonKeyManager and call unified methods.

### Specific actionable diffs to plan (high level)
- SwiftFFI.swift
  - Remove @unchecked Sendable on both classes, add private DispatchQueue serialization (or convert to actor).
  - getProfilePublicKey signature and return nil when hasKey == 0.
  - Remove debug prints in buildError.
  - Optionally, rename encrypt/decrypt local data methods to drop keyName parameter.

- Tests
  - Persistence/Symmetric/MessageCryptoInterop/ProfileKeyTests: adjust expectations for getProfilePublicKey optional; remove assumptions about keyName changing behavior.
  - MessageCryptoInterop: implement network encryption setup; allow mobile encryptForPublicKey; remove skips.
  - TransportBehaviour: add CA enrollment/certificate setup path; remove skip.

- Serializer
  - EnvelopeCrypto.swift: replace KeysHandle with CommonKeyManager; call encryptWithEnvelope/decryptEnvelope directly.

### On @unchecked Sendable: how to remove it properly
- Best-practice approach:
  - Make managers actors:
    - public actor NodeKeyManager: NodeOnly { … } and public actor MobileKeyManager: MobileOnly { … }
    - All methods become isolated to the actor; callers use await. This guarantees thread-safety around the FFI handle without @unchecked.
    - Tests: wrap calls in Task/await, use expectations for concurrency.
- Low-impact approach:
  - Keep classes non-Sendable and implement a private serial DispatchQueue for all FFI calls:
    - let queue = DispatchQueue(label: "NodeKeyManager.serial")
    - public func foo(...) throws -> T { try queue.sync { /* FFI call */ } }
    - Remove Sendable from protocols and classes.
    - Tests remain synchronous, concurrency tests pass deterministically.

Say the word and I’ll implement the preferred option end-to-end (including test fixes and serializer update), then run SwiftLint/SwiftFormat and the full test suite.

- Summary:
  - Found unsafe @unchecked Sendable with no internal sync; fix by actors or serial queue and remove Sendable constraints.
  - Align getProfilePublicKey to return optional; fix tests.
  - Local data crypto cannot select by key name; remove param and adjust tests.
  - Remove test skips by implementing network/transport setup flows.
  - Remove debug prints; update serializer to CommonKeyManager.
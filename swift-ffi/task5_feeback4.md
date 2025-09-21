[7 tools called]

- Root cause summary
  - The CA node is not fully initialized with valid Enrollment Authority (EA) public keys; as a result, certificate generation hasn’t occurred, and both rn_keys_ca_node_get_root_ca_certificate and rn_keys_ca_node_get_issuing_ca_certificate legitimately return 0 bytes. This manifests later as “InvalidCertificate(BadEncoding)” when the trust store tries to import empty DER.
  - Secondary contributors:
    - EA public key CBOR shape mismatch (single-key CBOR vs expected CBOR array of keys).
    - Missing strict validation after setupComplete; code proceeds even if CA has no generated certs.
    - Overuse of print() debug logging instead of the shared logger, making it harder to trace in CI.
    - Minor Swift 6 isolation details are fine here; not the cause for zero-length buffers.

- Evidence and alignment
  - Your test retrieves root/issuing certs immediately after setupComplete:
```97:101:swift-ffi/Tests/SwiftFFITests/FFIE2EIntegrationTest.swift
let rootCa = try await caNode.getRootCACertificate()
let issuingCa = try await caNode.getIssuingCACertificate()
try validateCertificates(rootCa: rootCa, issuingCa: issuingCa)
```
  - The FFI calls are correct, and `copyBytesAndFree` is used properly. Zero-length outputs indicate upstream CA state.
  - The setup path passes a single EA public key CBOR blob; Rust expects a CBOR array of keys for EA configuration and setup. If the format mismatches, the CA node setup will not produce certificates.

- Fixes (concrete and actionable)
  - Ensure EA public key format is a CBOR array of keys:
    - Current:
      - `eaPublicKeyCbor = try await eaManager.getPublicKey(eaHandle)` (likely a single CBOR-encoded key)
    - Change:
      - Wrap as array of keys, even if only one key is present.
      - Example:
        - let eaKeysArrayCbor = try CodableCBOREncoder().encode([eaPublicKeyCbor])
        - Use `eaKeysArrayCbor` instead of `eaPublicKeyCbor` in `setupComplete(params:)`.
      - Alternatively, expose a helper `EAKeyManager.getPublicKeysArrayCbor([handles]) -> Data` and use that.
  - Add post-setup validation guardrails:
    - Immediately after `setupComplete`, fetch root and issuing certs and assert non-empty; if empty, throw with a descriptive error:
      - “CA certificates unavailable; verify EA public keys CBOR array format.”
  - Replace print() with shared logger:
    - Use `RunarLogger` at `.debug` or `.trace` to log CA Node setup, EA keys length, and cert fetch lengths.
  - Defensive Swift checks in CANode extension:
    - If FFI returns code == 0 and outLen == 0, throw `FFIError.operationFailed("CA certificate is empty; ensure setupComplete received CBOR array of EA keys.")` instead of continuing. This fails fast near the root cause.

- Step-by-step verification
  - Before changes:
    - Log EA public key CBOR length and first few bytes to confirm shape (single key vs array).
  - Implement array-wrapping for EA keys; run:
    - `swift test --filter FFIE2EIntegrationTest.testWrapperFullTransportE2EQuicMtls`
  - Expect:
    - getRootCACertificate()/getIssuingCACertificate() outLen > 100, validateCertificates passes.
    - Trust store logs show proper non-zero lengths; no “BadEncoding”.

- Additional hardening (recommended)
  - Add a unit test that:
    - Calls `CANode.setupComplete` with a known-good EA keys CBOR array and immediately asserts both CA certificates are non-empty.
    - Calls with invalid EA public key shape (e.g., single-key CBOR not wrapped in an array) and asserts the operation fails fast with our new validation message.
  - Ensure `CAClient` config creation refuses empty root/issuing CA DER by throwing a clear error.

- Why this is not a Swift 6 actor/FFI isolation bug
  - Pointer lifetimes are correct: non-escaping closures and immediate copy/free.
  - Isolation is not the issue; the CA layer simply hadn’t created the chain due to incorrect EA configuration input.

- Minimal code changes (what to do now)
  - In `FFIE2EIntegrationTest`:
    - Replace `eaPublicKeyCbor` with a CBOR array:
      - let eaKeysArrayCbor = try CodableCBOREncoder().encode([eaPublicKeyCbor])
      - pass `eaKeysArrayCbor` to `CANode.CANodeSetupParams`.
  - In `CANode.setupComplete` and `get{Root,Issuing}CACertificate`:
    - Replace print() with `RunarLogger`.
    - Add fast-fail if cert length == 0 with a message that points to EA key CBOR array requirement.
  - Rerun tests; confirm non-zero DER sizes and absence of trust-store BadEncoding errors.

If you’d like, I can apply these changes and run the full suite to confirm green.
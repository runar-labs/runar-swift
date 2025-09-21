- Root cause
  - The CA Node isn’t fully configured with Enrollment Authority (EA) keys before setup; `rn_keys_ca_node_setup_complete` is being called with EA key data that the Rust side can’t parse (wrong shape). That leaves the internal CA uninitialized, so `rn_keys_ca_node_get_root_ca_certificate`/`…get_issuing_ca_certificate` return 0 bytes. The crash (signal 11) is a downstream symptom from the CA-side deref on invalid/empty EA keys and/or later trust-store use of empty certs.

- Why
  - EA public key format is not what the Rust FFI expects. The “EA public key” returned by `rn_keys_ca_get_ea_public_key` is a CBOR-encoded key. The CA Node APIs expect a CBOR-encoded array of keys, not a single-key CBOR blob.
  - The test doesn’t call `configureEnrollmentAuthority` before `setupComplete`, and passes a single-key CBOR directly to `setupComplete`. The Rust side either treats that as invalid or tries to parse and fails, leaving the CA certificate state empty (0 bytes). Later, adding a 0-byte cert to the trust store triggers “InvalidCertificate(BadEncoding)”. If Rust hits a null/invalid pointer path during setup, you’ll see the segfault.

- Confirming in your code
  - Test sequence (abbrev):
    - Get 1 EA public key via `EAKeyManager.getPublicKey(eaHandle)`.
    - Call `caNode.setupComplete(eaPublicKeys: eaPublicKeyCbor, …)`.
    - Immediately fetch root/issuing CA certs → 0 bytes.
  - `CANode.getRootCACertificate()`/`getIssuingCACertificate()` FFI wrappers are correct; zero-length conclusively means upstream CA never produced certs.
  - `setupComplete` Swift wrapper does copy locals and pass to FFI correctly.

- Fixes you should apply now
  1) Build EA keys as a CBOR array before setup
     - Convert the single-key CBOR to a CBOR array-of-keys.
       - Example:
         - let eaKeyCbor: Data = try await eaManager.getPublicKey(eaHandle)
         - let eaKeysArrayCbor = try CodableCBOREncoder().encode([eaKeyCbor])
     - Then either:
       - Call `try await caNode.configureEnrollmentAuthority(eaPublicKeys: eaKeysArrayCbor)` first, and pass the same `eaKeysArrayCbor` to `setupComplete`, or
       - If `setupComplete` already accepts the CA EA array as a single-shot config, pass `eaKeysArrayCbor` there. Don’t pass a single-key CBOR blob.
  2) Add post-setup validation and fail fast
     - Immediately after `setupComplete`, fetch both certs and assert non-zero lengths. If either is 0, stop and throw: “CA certificates unavailable; ensure EA public keys are CBOR array of keys.”
  3) Replace print() with `RunarLogger` and log key steps
     - Log EA keys CBOR length, whether configureEnrollmentAuthority was called, setupComplete success, and the lengths of root/issuing certs right after setup. This makes CI logs actionable.
  4) Harden Swift wrappers
     - In `getRootCACertificate()` and `getIssuingCACertificate()`, if `code == 0 && outLen == 0`, throw an explicit `FFIError.operationFailed("CA certificate is empty; verify EA keys CBOR array and setup sequence")` instead of returning empty `Data()`. This fails near the root cause.
  5) Test flow update (FFIE2EIntegrationTest)
     - Replace:
       - `let eaPublicKeyCbor = try await eaManager.getPublicKey(eaHandle)`
       - Passing that directly into setup
     - With:
       - `let eaKeysArrayCbor = try CodableCBOREncoder().encode([eaPublicKeyCbor])`
       - `try await caNode.configureEnrollmentAuthority(eaPublicKeys: eaKeysArrayCbor)`
       - `try await caNode.setupComplete(params: setupParams(with: eaKeysArrayCbor))`
       - `let rootCa = try await caNode.getRootCACertificate()`
       - `let issuingCa = try await caNode.getIssuingCACertificate()`
       - `XCTAssert(rootCa.count > 100 && issuingCa.count > 100)`

- Additional checks (if still failing)
  - Ensure networkId used in setup matches client/server configs.
  - Ensure you’re not using a “fake” shared handle or freeing CA handles prematurely. Keep CA Node alive (no deinit) through cert retrieval.
  - Confirm `configureEnrollmentAuthority`/`setupComplete` return `code == 0`, log the code on failure.
  - Enable Rust-side trace logging for CA setup to see exact parse errors (you already pipe `FFILogger.setLogLevel(.trace)`; keep it).

- Expected outcome
  - After passing a CBOR array of EA keys and calling `configureEnrollmentAuthority` (or providing the array directly to `setupComplete` if it’s single-step), the CA node will generate non-empty root/issuing certificates. Trust-store additions will succeed, and the `testWrapperFullTransportE2EQuicMtls` flow will proceed without segfaults.
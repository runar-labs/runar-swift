Missing items vs design.md:


- Recovery and multi-device
  - BIP‑39 mnemonic import/derivation.
  - SLIP‑0039 k‑of‑n shares.
  - Device‑to‑device transfer flow (ECDH session + user-verified code).
  - Tests for deterministic re-derivation across devices.

- TLS/QUIC
  - QUIC/TLS config builder facade (even if QUIC not in tests), including SNI usage and optional SPKI pinning.


- User-root storage (Done)
  - Use WhenUnlockedThisDeviceOnly (not AfterFirstUnlockThisDeviceOnly as now).
  - Add SecAccessControl requiring device unlock/biometry.
  - Explicitly set kSecAttrSynchronizable=false.

- Certificates (DONE)
  - Monotonic serials: pre-allocate/persist UInt64 and use it when issuing leafs.
  - Documented PoP is implied by CSR parsing; add explicit CSR PoP verification step during issuance.
  - SPKI pinning helper (export SPKI and compare bytes).

- Network key policy (Done)
  - Optional local retention as encrypted blob in Keychain (GenericPassword) for exportable network key (no plaintext persistence).
  - Helper APIs to store/load the encrypted blob.


- E2E tests (Done)
  - Single end-to-end test in Tests/ mirroring the Rust flow (not just the macOS host app).
  - Assertions for SAN, KeyUsage, EKU, SKI/AKI values; chain validation with SNI and optional pinning.

- Facade (done)
  - MobileKeyManagerV2 orchestrating root, profile/network derivations, CSR, CA/leaf issuance, certificate install/validate.

- ECIES/envelope(done)
  - Multi-recipient envelope helper (wrap same symmetric key to multiple recipients) per spec’s “multi‑recipient” test.

- Docs cleanup
  - CSR: Keep only message-signed path; we removed digest path in code—document both worked, message chosen.
  - Note SKI/AKI = SHA‑1 over SPKI DER (RFC 5280). We implemented this.

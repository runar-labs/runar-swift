- Curve/hash
  - P-256 everywhere. ECDSA-SHA-256 for signatures. ECDH P-256 for ECIES. HKDF-SHA-256 for all derivations.
  - ECIES info: "runar-v1:ecies:envelope-key". AES-256-GCM.

- Key classes and where/how stored
  - user-root (derivation master, never leaves device)
    - Recovery-first: derive user-root from a mnemonic (BIP-39 style) + optional passphrase. Convert mnemonic to seed per BIP-39, then HKDF-SHA-256 to 32 bytes root secret.
    - Store root secret as a GenericPassword item in Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecAttrSynchronizable=false). Protect with AccessControl requiring device unlock/biometry. Use only as IKM for HKDF; never used directly for crypto.
  - node-identity.signing (CSR/TLS)
    - Non-extractable Secure Enclave key (P-256) with kSecAttrTokenIDSecureEnclave, kSecAttrIsPermanent=true, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecAttrSynchronizable=false.
    - CSR signing via SecKeyCreateSignature (ecdsaSignatureMessageX962SHA256).
    - Determinism: this key is device-local and not re-derivable across devices (SE keys are non-importable). On device replacement, a new node-identity signing key will be created and a new certificate issued.
  - profile.agreement (encrypt/decrypt envelopes)
    - Deterministically derived from user-root via HKDF-SHA-256. Private material never leaves device. Keep in memory (derive on demand); do not persist plaintext; no Secure Enclave (needs deterministic re-derivation on new device).
  - network.agreement (used to encrypt/decrypt envelope keys; also network ID = compactId(pub))
    - Deterministically derived from user-root via HKDF-SHA-256. Exportable to nodes as policy requires. When exporting, wrap immediately via ECIES and never persist plaintext. If retained locally, persist only an encrypted blob in Keychain (GenericPassword, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecAttrSynchronizable=false). Not Secure Enclave.

- Certificates and CSR
  - CSR: PKCS#10, PoP required; subject CN=DNS-safe node-id; SAN required (server-side computed DNS/IP).
  - CA (root): BasicConstraints CA pathLen=0; KeyUsage keyCertSign+cRLSign; SKI/AKI; ~10y.
  - Leaf (node): BasicConstraints notCA; KeyUsage digitalSignature; EKU serverAuth+clientAuth; SANs; SKI/AKI; 90–365d.
  - Monotonic serials: pre-allocate UInt64, persist before issuance.

- TLS/QUIC
  - SNI=DNS-safe node-id.
  - Anchor to CA (SecTrustSetAnchorCertificates) and evaluate.
  - Hostname validation via SNI.
  - Optional SPKI pinning (compare leaf SPKI).

- IDs
  - base64url(no padding) of the first 16 bytes of SHA-256(pubkey) for node/profile/network.

- Keychain attributes
  - Non-extractable SE keys: kSecAttrTokenIDSecureEnclave, kSecAttrIsPermanent=true, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecAttrSynchronizable=false.
  - Derived software keys (profile/network): hold in memory or store only encrypted scalar in GenericPassword (WhenUnlockedThisDeviceOnly, not synchronizable). Never store plaintext.

- Testing
  - SE CSR path (sign with SecKeyCreateSignature); certificate issuance; chain validation with SecTrust; SNI and SPKI pinning checks.
  - Profile envelope encryption: multi-recipient, decrypt on-device only; keys re-derived on restore.
  - Network export: deterministically derive, wrap to node, unwrap on node; no plaintext persistence.
  - Deterministic derivations; purpose separation; monotonic serials.

- Root key recovery
  - Use a 12/24-word mnemonic (BIP-39 compatible) with optional passphrase. Derive seed per BIP-39; derive user-root with HKDF-SHA-256 from that seed.
  - On new device: user enters mnemonic (+passphrase) → re-derive user-root → deterministically re-derive profile and network agreement keys and identifiers.
  - Node-identity signing key is device-local SE and will be newly created on each device. A new CSR/certificate will be issued for that device.

- Additional recovery methods
  - Shamir’s Secret Sharing (SLIP-0039): split the user-root into n mnemonic shares with k-of-n threshold. Any k shares reconstruct the same user-root, enabling deterministic re-derivation of all profile/network keys. Shares should be stored encrypted at rest (e.g., device Keychain GenericPassword) and never synchronized.
  - Device-to-device transfer (no iCloud): establish an authenticated E2E session (QR-assisted ECDH/BLE/Wi‑Fi) with user-verified short code; require biometry/consent to export; wrap the user-root in a session key; import on the new device into Keychain GenericPassword (WhenUnlockedThisDeviceOnly, not synchronizable).

- Multi-device policy
  - Multiple iOS devices for the same user MUST share the same user-root. Supported methods: BIP‑39 mnemonic import or secure device-to-device transfer. The user-root is NEVER shared with nodes.
  - Deterministic re-derivation on every device ensures identical profile/network agreement keys and identifiers. Node-identity signing keys remain device-local and will receive new certificates per device.

- Out of scope (current version)
  - profile.signing and network.signing are NOT required now. Only agreement keys are used for envelope encryption in these scopes.

- User-root storage (final)
  - The user-root is a raw secret stored as Keychain GenericPassword (kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecAttrSynchronizable=false) protected by AccessControl with device unlock/biometry. It is used only as HKDF input for deterministic derivations and is never stored inside Secure Enclave.

Implementation plan (clean, P‑256 spec)

- Strategy
  - No backward compatibility. Remove legacy code and tests. Build a clean implementation aligned to this spec.
  - Keep components small and well‑tested; wire them via an end‑to‑end test demonstrating all data flows.

- Phases

  1) Core primitives (P‑256 + HKDF‑SHA‑256)
  - `KeyDeriver.swift`: HKDF‑SHA‑256 helpers with salt/info format specified here. Unit tests for deterministic output and purpose separation.
  - `Ids.swift`: compactId generation (base64url of first 16 bytes of SHA‑256(pubkey)). Tests for stability and cross‑case.

  2) Key classes and storage policy
  - `UserRootStore.swift`: Keychain GenericPassword storage (WhenUnlockedThisDeviceOnly, not sync) with AccessControl; load/save API. Tests for add/get/delete and attribute verification.
  - `ProfileKeys.swift`: derive profile agreement keys from user‑root; in‑memory only; never persisted. Tests for deterministic re‑derivation and encryption/decryption round‑trip using ECIES.
  - `NetworkKeys.swift`: derive network agreement keys from user‑root; provide export API that outputs only ECIES‑wrapped scalars; optional encrypted at‑rest blob (GenericPassword) if retained. Tests for deterministic re‑derivation, export (wrap), import (unwrap) on node side, and no plaintext persistence.
  - `NodeIdentitySigning.swift`: create Secure Enclave P‑256 non‑extractable signing key (per device), lookup by label/tag; attribute checks. Tests: key exists, SecKeyCopyExternalRepresentation fails, can sign.

  3) CSR and CA
  - `CSRBuilder.swift`: build CertificationRequestInfo via swift‑certificates; sign with SecKeyCreateSignature (ECDSA SHA‑256); assemble PKCS#10. Tests: PoP verified by swift‑certificates; CN policy enforcement.
  - `CertificateAuthority.swift`: P‑256 CA and leaf issuance; pathLen=0, EKUs, SANs, SKI/AKI, monotonic serials with pre‑allocation/persist. Tests for extension presence and serial behavior.

  4) TLS validation utilities
  - `CertificateValidator.swift`: SecTrust chain validation anchored to CA; hostname validation using SNI; SPKI pinning option. Tests: success/failure cases and pinning mismatch.

  5) Manager façade
  - `MobileKeyManagerV2.swift`: orchestrates user‑root storage, profile/network derivations, node‑identity key creation, CSR emission, certificate installation, and QUIC config building. Keep APIs minimal and spec‑aligned. Unit tests per function.

  6) End‑to‑end test (single, readable flow)
  - Mirrors rust `end_to_end_test.rs`:
    - Create user‑root; derive profile/network keys; show compact IDs.
    - Create node‑identity signing key (SE); build CSR; issue leaf from CA; install chain; validate with SecTrust.
    - Envelope encrypt with profile and network recipients; decrypt locally.
    - Export network agreement key for a node (ECIES wrapped); unwrap on node; verify decrypts.
    - QUIC/TLS config assembly and SPKI pinning check (logic only if QUIC not available in unit tests).

- Test matrix (high‑level)
  - Key derivation: determinism across devices (same mnemonic), separation across purposes/scopes, invalid scalar retry (if implemented).
  - Secure Enclave node‑identity: non‑extractable, sign works.
  - ECIES: envelope layout, multi‑recipient, decrypt success/failure.
  - CSR/CA: PoP verified; CN/SAN policies; serial monotonicity; extension correctness.
  - TLS validator: anchor, hostname match, SPKI pinning.
  - E2E: full flow executes and validates invariants.

- Acceptance criteria
  - All unit and E2E tests pass locally and in CI.
  - No deprecated/legacy P‑384 paths remain; only P‑256 code.
  - Security attributes verified in tests (Keychain accessibility, no synchronizable, non‑extractable where required).

Assessment: refactor vs rebuild

- Rebuild (recommended):
  - The current codebase is P‑384‑centric with mixed import/export paths and CSR signing via CryptoKit scalars. Switching to P‑256, Secure Enclave non‑extractable CSR signing, and deterministic derivations is a conceptual pivot. Implementing V2 cleanly under `RunarKeysV2` with fresh tests will be faster and safer than piecemeal refactoring. After green, delete legacy and rename.
- Refactor (alternative):
  - Possible but riskier; may leave residual assumptions and increase churn. Only choose if binary/API compatibility is mandatory (not the case here).
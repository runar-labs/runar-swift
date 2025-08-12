LEts address all these issues onew by one.

ADJUST existing tests if thney conflict with these changes and create new tests to cover new scenarios.

Check Apples docs and examples to avoid guesswork and trial adn error.

Think from first principles, undertstand deeplly the APIs and specs before making design decision and making code changes. to avoid trial and error approach.

Think deep , think wide.

Behave as an expert Apple swift developer. Expert security developer, expert certificates and encryption specialist.

No hacks, no shortcuts, no simplifications. If tyou get stuck stop and ask for advice.

- SANs are hardcoded
  - Current: static `localhost`, `runar.test`.
  - Fix:
    - Populate SANs from the real node identity used at connection time: DNS names (SNI) and/or IP addresses (iPAddress).
    - For node-id based names, use a DNS-safe CN and mirror it in SAN DNS entries.
    - Do not rely on CN matching; SAN must contain the identity used by the client.
  - Where: `Certificate.swift` in `createEndEntityExtensions(...)`.

- Proof-of-possession and CSR enforcement
  - Current: `MobileKeyManager.processSetupToken` issues certs directly from public key; CSR path exists but is not enforced.
  - Fix:
    - Require a PKCS#10 CSR signed by the node’s private key.
    - Verify CSR signature (PoP).
    - Validate CSR subject CN equals DNS-safe node-id; reject on mismatch.
    - Read requested SANs from CSR (extensionRequest) and propagate into the leaf cert (or compute SANs server-side deterministically).
  - Where:
    - Enforce CSR in `MobileKeyManager.processSetupToken(...)`.
    - Include SANs in `CertificateRequest.create(...)` via extensionRequest.

- CA constraints
  - Current: CA has `BasicConstraints.isCertificateAuthority(maxPathLength: nil)`.
  - Fix:
    - Prefer `maxPathLength: 0` for a root issuing directly to leaves (prevents unintended intermediates).
  - Where: `createCAExtensions(...)`.

- Revocation/AIA metadata (optional but best-practice for PKI)
  - Current: none.
  - Fix:
    - Add Authority Information Access (CA Issuers URL, OCSP URL) and CRL Distribution Points if you intend to do revocation or distribution by URL. If revocation will not be used in this environment, document that and skip.
  - Where: `createCAExtensions(...)`, `createEndEntityExtensions(...)`.

  NO Intention to do  revocation or distribution by URL - Document this in the code.

- Serial numbers
  - Current: `Certificate.SerialNumber()` (random) and an internal `serialCounter` that is not used for leaf issuance.
  - Fix:
    - Ensure serial is positive, unique, and ≤ 20 bytes (swift-certificates already enforces reasonable shape).
    - If you want auditability like Rust, use monotonic serials persisted via `serialCounter`.
  - Where: `CertificateAuthority.signCertificateRequest(...)` and/or leaf creation.

- Leaf KeyUsage and EKU
  - Current: `digitalSignature` only; EKU serverAuth+clientAuth; good for mTLS.
  - Consider:
    - If you’ll never use client auth on some roles, narrow EKU accordingly per role profile.
    - Do not add `keyEncipherment` for ECDSA (keeping it absent is correct).

- Validity windows
  - Current: CA 10 years; leaves 1 year.
  - Consider:
    - Shorten leaf validity (e.g., 90–180 days) to reduce revocation reliance.
    - Keep -60s notBefore skew to avoid clock drift issues.

- DN handling
  - Current: DN parsing supports CN, C, O; throws on unknown attributes.
  - Consider:
    - Support common attributes (ST, L, OU) or ignore unknowns rather than failing, since CSRs may include them.
  - Where: `parseDistinguishedName(...)` in both CSR and leaf paths.

- Peer validation at use
  - Current: `CertificateValidator.validateCertificateChainWithSecTrust` exists; QUIC config returns `SecKey` + chain.
  - Ensure:
    - The QUIC transporter performs SecTrust evaluation anchored to your CA and performs hostname/IP matching against SANs.

### CSR robustness vs Rust

- Yes, Rust is more robust today:
  - Verifies CSR signature (PoP).
  - Enforces CN equality with DNS-safe node id.
  - Signs via CA, and validates time bounds at install.
- Swift gaps to reach “state of the art”:
  - Always require and verify PKCS#10 CSR.
  - PoP: verify CSR signature before issuing.
  - Enforce subject policy (CN normalization and match).
  - Carry SANs via CSR extensionRequest, or recompute server-side.
  - Reject empty/invalid CSRs; provide precise errors.

### Concrete Swift changes

- In `MobileKeyManager.processSetupToken(...)`
  - Replace public-key issuance with CSR-only path:
    - Parse CSR.
    - Verify CSR signature (PoP).
    - Extract/validate CN against DNS-safe node id.
    - Extract requested SANs or compute SANs and pass to leaf builder.
    - Use persisted `serialCounter` for serial (optional).

- In `CertificateRequest.create(...)`
  - Allow injecting SANs into CSR via `extensionRequest` so the CA can honor them.

- In `CertificateAuthority` leaf creation
  - Use CSR’s SANs when present; otherwise compute SANs (DNS/IP).
  - Keep EKU and KeyUsage as-is for ECDSA; add SKI/AKI (already present).
  - Add AIA/CRLDP if revocation/distribution is required.
  - CA: set `maxPathLength: 0`.

- In `CertificateValidator`
  - Prefer `validateCertificateChainWithSecTrust` with CA anchors for production; optionally add DN order-insensitive matching when SecTrust isn’t available.

- Tests to add/update
  - CSR PoP: tamper with CSR to ensure issuance fails.
  - CN/SAN policy: mismatched node id should be rejected; missing SAN should fail hostname validation.
  - AIA/CRLDP presence if you decide to include them.
  - Serial policy: ensure uniqueness and size constraints.

- Optional interoperability alignment
  - Add P-256 support (ECDSA-SHA256) alongside P-384; pick one system-wide. - NO changes we will continue using P-384
  - Ensure SANs encode IP when connecting by IP; encode node FQDN when using SNI.



- Private key serialization and transport
  - Rust (network key distribution): sends PKCS#8 DER-encoded private key over ECIES.
  - Swift: sends raw scalar bytes over ECIES.
  - Best practice: pick one canonical encoding (PKCS#8 preferred for portability) and enforce it.
  CHANGE SWWIFT SIZE to align with Rust and use proper PKCS#8

- Key separation
  - Swift: You’re close—keep ECIES on `ECDHKeyPair`; optionally stop converting the same scalar for signing by generating a separate signing key (or derive with a context label).
  Introduce a dedicated ECDH key for ECIES (separate from ECDSA signing), or derive two distinct keys from a master via HKDF with disjoint context labels (“signing-key” vs “agreement-key”), and update ECIES to use the agreement key.

- Where to change (files)
  - `Sources/RunarKeys/MobileKeyManager.swift` (CSR enforcement, serial usage).
  - `Sources/RunarKeys/Certificate.swift` (CA pathLen=0; SANs from identity; optional AIA/CRLDP).
  - `Sources/RunarKeys/CryptographicTypes.swift` (if adding P-256 support).
  - Tests under `Tests/RunarKeysTests/*` (new CSR and validation cases).

- Summary
  - Enforce CSR + PoP; fix SAN handling to reflect actual identities; tighten CA constraints; optionally add AIA/CRLDP; consider shorter leaf validity; ensure SecTrust hostname/IP checks. With these, Swift reaches 100% TLS best-practice for an ECDSA private PKI.

- What I just did and next
  - Reviewed Swift code paths and highlighted concrete gaps and file targets. If you want, I can draft the specific edits for `processSetupToken` and `createEndEntityExtensions` to enforce CSR and dynamic SANs.
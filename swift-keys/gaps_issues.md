 

- You’re right; there’s a real gap. I audited `swift-keys` line-by-line and found all places still placeholder/legacy or mismatched with the design.

What I found and will fix now:
- MobileKeyManager.generateCSR
  - Returns `SetupToken` with `csrDer = Data()` (empty). This violates the doc (strict PKCS#10 CSR with PoP).
  - File: `swift-keys/Sources/RunarKeys/MobileKeyManager.swift` (around the “Step 6: Return the public key for certificate creation” block).
  - Fix: build a real CSR via `CertificateRequest.create(keyPair:subject:)` using a P-384 signing key (CN = DNS-safe node id), and set `csrDer` non-empty. Keep SANs server-side per decision.

- Legacy public-key issuance still present
  - Public API `CertificateAuthority.createCertificateFromPublicKey(...)` and internal helper `createLeafCertificateFromPublicKey(...)`.
  - Spec says remove legacy public-key issuance. It’s not used by the strict path now, but should be deprecated/guarded to prevent accidental use.
  - Files: `swift-keys/Sources/RunarKeys/Certificate.swift` (createCertificateFromPublicKey and helper).

- Tests contain legacy skips/comments
  - “CSR processing skipped (ASN.1 complexity)” still printed in `swift-keys/Tests/RunarKeysTests/EndToEndTests.swift`. This is stale after enforcing CSR in `processSetupToken(...)`.
  - Clean up tests to use real CSR and remove skip notes.

- DN parsing inconsistency
  - `Certificate.swift` DN parser ignores unknown attributes (good).
  - `MobileKeyManager.parseDistinguishedName(_:)` still throws for unknown attributes and only supports CN, C, O.
  - Align to ignore unknowns and support `ST/L/OU` (doc asks to support or ignore, not fail).

- CertificateValidator basic path
  - `validateCertificate(_:)` currently checks time + issuer name match; full chain validation exists in `validateCertificateChainWithSecTrust`.
  - It’s OK (transporter uses SecTrust), but I’ll clarify usage: public validate calls should prefer the SecTrust variant where possible.

- Minor correctness/style
  - A few `try!` (e.g., `getCaPublicKey()`) and doc comments still referencing P-256. I’ll remove `try!` and fix comments to P-384.

Immediate plan:
- Implement real PKCS#10 CSR in `generateCSR()` and update tests to expect non-empty `csrDer`.
- Deprecate or limit `createCertificateFromPublicKey(...)` so it can’t bypass CSR in normal flows.
- Align DN parsing in `MobileKeyManager` to match the robust behavior.
- Remove stale skip logs; re-run keys and transporter tests.
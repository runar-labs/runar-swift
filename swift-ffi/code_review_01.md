Code Review:

### Executive summary
- Overall, the Swift wrapper is solid: consistent error handling, correct memory management, and good API organization.
- Major missing coverage: persistence/keystore APIs, several mobile/network-key flows, CA-node direct “handle_*” endpoints, CA-client get_crl, symmetric keys, node identity APIs, and a few transport/decryption utilities.
- Tests: Good E2E coverage for CA/QUIC and wrapper-only flows, plus transport/discovery files exist; however, parity with the Rust test suite is not yet complete.

## Review scope
- Swift sources: `swift-ffi/Sources/SwiftFFI/SwiftFFI.swift`
- Header: `runar-rust/runar-ffi/include/runar_ffi.h`
- Rust tests: `runar-rust/runar-ffi/tests/*`
- Swift tests: `swift-ffi/Tests/SwiftFFITests/*`

### Design and API quality
- Error handling
  - Consistent “withRnError” wrapper and typed `FFIError`. Good.
  - Message extraction frees `rn_string_free` reliably. Good.
  - One inconsistency: only `setLocalNodeInfo` tries `rn_last_error` on failure; everything else relies on `RNAPIRnError`. This is fine; `RNAPIRnError` is the primary channel. Keep `rn_last_error` only for legacy code paths that do not use error structs (which you’ve already done).

- Memory management and safety
  - Every out buffer returned by FFI is copied by `copyBytesAndFree` then freed with `rn_free`, and c-strings are copied then freed with `rn_string_free`. Good.
  - No use-after-free patterns observed.
  - All `deinit` paths free Rust-side handles (`rn_keys_free`, `rn_transport_*_free`, `rn_discovery_free`, `rn_keys_ca_node_free`, `rn_keys_ca_node_free_shared`, `rn_transport_ca_client_free`). Good.

- Swift API surface
  - Clear separation between Keys, CA Node/Server, CA Client, Transport, and Discovery handles.
  - Good use of `Codable` CBOR models for protocol data.
  - A few APIs conflate responsibilities in a single type (`KeysHandle` doing both node and mobile), but given the FFI shape this is acceptable.

- Thread-safety
  - No explicit synchronization or thread-safety guarantees. This mirrors Rust side where handles are not guaranteed thread-safe. Document “not thread-safe; confine to one actor/queue”.

### API coverage vs runar_ffi.h

Below, “missing” means not wrapped in Swift; “covered” means present.

- Logger and last error
  - rn_set_log_level: covered via `FFILogger.setLogLevel`
  - rn_set_logger_node_id: covered via `FFILogger.setLoggerNodeId`
  - rn_last_error: used only in `setLocalNodeInfo` for legacy return paths. OK.

- Persistence / keystore / state
  - rn_keys_set_persistence_dir: missing
  - rn_keys_enable_auto_persist: missing
  - rn_keys_wipe_persistence: missing
  - rn_keys_get_keystore_caps: missing
  - rn_keys_flush_state: missing
  - rn_keys_register_apple_device_keystore: missing
  - rn_keys_register_linux_device_keystore: intentionally omit (non-Apple)

- NodeInfo / identity
  - rn_keys_set_local_node_info: covered via `KeysHandle.setLocalNodeInfo`
  - rn_keys_node_get_public_key: covered via `getNodePublicKey`
  - rn_keys_node_get_agreement_public_key: missing
  - rn_keys_node_get_node_id: missing

- Node and mobile initialization
  - rn_keys_new, rn_keys_init_as_node, rn_keys_init_as_mobile: covered

- CSR / enrollment message conversion
  - rn_keys_node_generate_csr: covered
  - rn_keys_mobile_process_setup_token: covered (mobile process)
  - rn_keys_mobile_from_enroll_response / rn_keys_mobile_from_renew_response: covered

- QUIC certificate config and node certificate
  - rn_keys_node_get_quic_certificate_config: covered
  - rn_keys_node_get_node_certificate: covered

- Envelope encryption/decryption
  - rn_keys_node_encrypt_with_envelope: covered
  - rn_keys_mobile_encrypt_with_envelope: covered
  - rn_keys_node_decrypt_envelope: missing (Swift provides decrypt_with_profile and mobile decrypt envelope; consider parity)
  - rn_keys_mobile_decrypt_envelope: covered
  - rn_keys_node_decrypt_with_profile: covered

- Symmetric/local data encryption
  - rn_keys_encrypt_local_data: missing
  - rn_keys_decrypt_local_data: missing
  - rn_keys_ensure_symmetric_key: missing

- Mobile network key management
  - rn_keys_mobile_initialize_user_root_key: covered
  - rn_keys_mobile_get_user_public_key: covered
  - rn_keys_mobile_derive_user_profile_key: covered
  - rn_keys_mobile_install_network_public_key: missing
  - rn_keys_mobile_generate_network_data_key: missing
  - rn_keys_mobile_has_network_private_key: missing
  - rn_keys_mobile_create_network_key_message: missing

- Message crypto (node <-> mobile, network, public key)
  - rn_keys_encrypt_message_for_mobile: missing
  - rn_keys_decrypt_message_from_mobile: missing
  - rn_keys_encrypt_message_for_node: missing
  - rn_keys_mobile_decrypt_message_from_node: missing
  - rn_keys_encrypt_for_public_key: missing
  - rn_keys_encrypt_for_network: missing
  - rn_keys_decrypt_network_data: missing

- Certificate utilities/status
  - rn_keys_certificate_extract_ski / get_serial: covered via `CertificateUtils`
  - rn_keys_node_get_certificate_status: missing
  - rn_keys_node_get_certificate_serial: missing (get_serial exists for DER, but this API queries via keys handle)
  - rn_keys_node_validate_peer_certificate: missing

- Network key (node side)
  - rn_keys_node_install_network_key: missing
  - rn_keys_node_get_network_agreement: missing
  - rn_keys_node_has_network_private_key: missing

- CA Node lifecycle and EA
  - rn_keys_ca_node_new/free/create_shared/free_shared: covered
  - rn_keys_ca_node_add_admin_ski: covered (via SharedCANode)
  - rn_keys_ca_create_ea_key_pair / get_ea_public_key / free_ea_key_pair: covered (EAKeyManager)
  - rn_keys_ca_node_setup_complete: covered
  - rn_keys_ca_node_configure_enrollment_authority: missing

- CA Node direct HTTP handlers (serverless path)
  - rn_keys_ca_node_handle_enroll/renew/revoke/chain/status/crl: only CRL is wrapped via `handleCRL`. Others missing.
  - rn_keys_ca_get_certificate_der / _subject, rn_keys_ca_free: missing (lower-level CA query APIs)

- CA Server
  - rn_transport_ca_server_new/start/stop/free/get_bootstrap_addr/get_authenticated_addr/configure_admin_skis: covered on `CAServer`

- CA Client
  - rn_transport_ca_client_new_with_config/free/enroll/renew/revoke/get_chain/get_status: covered
  - rn_transport_ca_client_get_crl: missing

- Discovery
  - rn_discovery_new_with_multicast/free/init/bind_events_to_transport/start_announcing/stop_announcing/shutdown/update_local_peer_info: covered (DiscoveryHandle)

- Transport
  - rn_transport_new_with_keys/free/start/poll_event/connect_peer/disconnect_peer/is_connected/update_local_node_info/request/publish/complete_request/stop/local_addr: covered via `TransportHandle`

- Compact ID
  - rn_keys_get_compact_id: covered

- CA token management
  - rn_keys_ca_node_revoke_token: covered
  - rn_keys_ca_node_generate_crl_lite: not present in header’s current section? Header includes rn_keys_ca_node_handle_crl and rn_transport_ca_client_get_crl; also defines rn_keys_ca_node_generate_crl_lite at bottom. This is missing in Swift.

### Tests parity vs Rust
- Swift present:
  - Wrapper E2E for CA/QUIC flows.
  - Baseline E2E test also present.
  - Keys E2E test covers mobile init, node CSR, profile keys, envelope crypto.
  - Quic transport and discovery tests present (need to inspect thoroughness, but files exist).

- Missing Swift-side test coverage (relative to Rust tests):
  - comprehensive_ffi_test.rs: covers many APIs including persistence, symmetric keys, keystore caps, device keystore registration, certificate status/serial via keys, network key flows (install_network_public_key, generate_network_data_key, has_network_private_key), encryption to specific public keys and networks, decrypt_network_data: not yet covered.
  - initialization_test.rs / lifecycle_test.rs / keys_state_test.rs / keys_state_step_test.rs: initialization/persistence/keystore behavior tests are not mirrored in Swift; no wrappers exist for many of these APIs yet.
  - ffi_transport_test.rs: Swift has transport wrappers and tests, but parity around request/publish/complete_request flows and event polling should be ensured to match scenarios (timeouts, invalid inputs, multiple peers).
  - ffi_e2e_integration_test.rs: Swift E2E mirrors enrollment/renew/revoke/status/chain; good.

### Security and robustness
- No fallbacks or silent failures observed. On non-zero codes, errors are thrown with messages. Good.
- Inputs validated at Swift layer (minimal) and fully validated by Rust. Consider:
  - Reject zero-length buffers at Swift boundary for functions that require non-empty data.
  - Explicitly document for each public API what errors to expect (e.g., invalid arguments, not initialized, wrong manager type).
- Key persistence APIs are missing; without them, lifecycle across restarts is not validated in Swift.

### Documentation
- Public API lacks doc comments for many methods (exceptions: several have brief descriptions). Recommend adding `///` doc blocks consistently (parameters, errors thrown, Rust parity note).
- Add a top-level README in `swift-ffi` describing architecture, mapping, error semantics, and memory model.

## Actionable recommendations

- High priority (cover essential FFI surface)
  - Persistence/keystore/state:
    - Wrap and test: `rn_keys_set_persistence_dir`, `rn_keys_enable_auto_persist`, `rn_keys_wipe_persistence`, `rn_keys_get_keystore_caps`, `rn_keys_flush_state`, `rn_keys_register_apple_device_keystore`.
  - Node identity:
    - Wrap and test: `rn_keys_node_get_node_id`, `rn_keys_node_get_agreement_public_key`.
  - Certificate status:
    - Wrap and test: `rn_keys_node_get_certificate_status`, `rn_keys_node_get_certificate_serial`, `rn_keys_node_validate_peer_certificate`.
  - CA client:
    - Wrap `rn_transport_ca_client_get_crl`.
  - CA node serverless handlers:
    - Optionally wrap direct “handle_*” APIs for “embedded serverless” testing: `handle_enroll`, `handle_renew`, `handle_revoke`, `handle_chain`, `handle_status` to enable unit tests without server.
  - Network key and message crypto flows:
    - Wrap and test mobile network key flows: `rn_keys_mobile_install_network_public_key`, `rn_keys_mobile_generate_network_data_key`, `rn_keys_mobile_has_network_private_key`, `rn_keys_mobile_create_network_key_message`.
    - Wrap and test message crypto: `rn_keys_encrypt_message_for_mobile`, `rn_keys_decrypt_message_from_mobile`, `rn_keys_encrypt_message_for_node`, `rn_keys_mobile_decrypt_message_from_node`, `rn_keys_encrypt_for_public_key`, `rn_keys_encrypt_for_network`, `rn_keys_decrypt_network_data`.
  - Symmetric keys:
    - Wrap `rn_keys_ensure_symmetric_key`, `rn_keys_encrypt_local_data`, `rn_keys_decrypt_local_data`.

- Medium priority
  - Node/network key (node side): `rn_keys_node_install_network_key`, `rn_keys_node_get_network_agreement`, `rn_keys_node_has_network_private_key`.
  - Enrollment token utilities: if needed beyond EAKeyManager, expose `rn_keys_enrollment_token_generate` and `rn_keys_enrollment_token_validate` as low-level utilities (note: ensure no key material leakage).
  - CA/EA additional utilities: `rn_keys_ca_get_certificate_der`, `rn_keys_ca_get_certificate_subject`, `rn_keys_ca_free` (only if you expose low-level CA handles beyond current `CANode`).
  - Wrap `rn_keys_ca_node_configure_enrollment_authority` to allow setting EA without setupComplete re-run.
  - CA node generate CRL lite (explicit API): `rn_keys_ca_node_generate_crl_lite` (you currently rely on handle_crl).

- Tests to add (mirror Rust; exclude Linux-only)
  - Persistence lifecycle: set persistence dir, enable auto-persist, wipe, flush; verify state continuity across handle re-creation.
  - Keystore caps / Apple device keystore registration.
  - Full mobile network key exchange and message encryption flows (both directions).
  - Symmetric key creation and local data encrypt/decrypt.
  - Node certificate status/serial via keys handle; peer cert validation.
  - CA client get_crl parity test.
  - Transport request/publish/complete flows with event polling and multiple peers; negative cases (timeouts, invalid CBOR).
  - Node id and agreement public key retrieval (and use them in flows).

- API ergonomics
  - Consider splitting `KeysHandle` into `NodeKeys` and `MobileKeys` wrappers to better constrain allowed methods per initialization state (reduces “wrong manager type” errors).
  - Document thread-safety: “not thread-safe; confine to one queue/actor.”
  - Add precondition checks for non-empty inputs where appropriate.

- Documentation
  - Add doc comments to all public methods with:
    - Parameters, returns, throws, and Rust parity notes (function name in C).
  - Top-level README with API sections and examples for common flows.

## Suggested structure for new tests (file-level)
- `Tests/SwiftFFITests/PersistenceTests.swift`
  - persistence dir, auto-persist, wipe, flush, keystore caps, apple device keystore registration.
- `Tests/SwiftFFITests/NetworkKeyFlowTests.swift`
  - mobile install/generate/has/create_message, node install/get_agreement/has_private.
- `Tests/SwiftFFITests/MessageCryptoInteropTests.swift`
  - encrypt_for_mobile/node + decrypt counterpart; encrypt_for_public_key; encrypt_for_network/decrypt_network_data.
- `Tests/SwiftFFITests/SymmetricKeyTests.swift`
  - ensure_symmetric_key + encrypt/decrypt local data.
- `Tests/SwiftFFITests/CertificateStatusTests.swift`
  - certificate status/serial via keys; peer certificate validation.
- `Tests/SwiftFFITests/CaClientCrlTests.swift`
  - get_crl parity and rejection scenarios.
- `Tests/SwiftFFITests/TransportBehaviourTests.swift`
  - request/publish/complete/poll_event with multiple peers; negative cases.

## Notable strengths
- Clean memory handling and deinit patterns.
- Consistent error propagation; deterministic without fallbacks.
- Comprehensive E2E baseline parity for CA/QUIC flows.
- Discovery and transport wrappers present with sane CBOR helpers.

## Risks and gaps
- Missing persistence/keystore APIs means production lifecycle and OS keystore integration are not validated on Swift.
- Missing network key/message crypto flows reduces mobile/node end-to-end parity.
- Missing CA-client get_crl and CA-node serverless handlers limits flexibility in testing and diagnostics.
- No thread-safety guarantees; document usage constraints.

## Conclusion
The library is in a strong state for the CA/QUIC path and basic keys/profile/envelope flows. To reach full parity with `runar-ffi` and Rust tests (excluding Linux), implement the missing wrappers above, add the proposed test suites, and augment documentation. This will ensure comprehensive coverage, robust lifecycle handling, and production readiness across Apple platforms.
## Swift Node over Rust FFI: Goals, Design, and Work Plan

### Executive summary
- Goal: Implement a new Swift library `swift-node` that provides the Runar Node runtime in Swift, using existing Swift libraries (`swift-common`, `swift-serializer`, `swift-serializer-macros`) but replacing Swift implementations of keys and transporter with Rust crates via a unified FFI (`runar-rust/runar-ffi`).
- Rationale: Consolidate cryptography and networking in Rust for correctness and performance while keeping the service model and developer ergonomics in Swift.
- Deliverables: A packaged `swift-ffi` module wrapping the Rust `runar_ffi` library, a `swift-node` library that mirrors the Rust Node APIs, integration with `swift-serializer`, and full build/test pipelines for iOS/macOS.

### Scope and non-goals
- In scope:
  - A Swift-native Node runtime that delegates keys and transport operations to Rust via FFI.
  - A single Rust FFI dylib/staticlib (`runar_ffi`) exposing both keys and transporter.
  - A Swift package `swift-ffi` that wraps `runar_ffi` symbols and manages memory and errors.
  - Alignment of serialization/encryption with Swift `RunarSerializer` by providing an FFI-backed keystore implementation.
  - Packaging for iOS/macOS (XCFramework), and samples/tests.
- Out of scope (phase 1):
  - Exposing the full Rust `runar_node` over FFI. We reimplement Node control-plane in Swift to keep Swift ergonomics and tooling.
  - Android/NodeJS bindings.

---

## Current state (verified from code)

### Rust unified FFI (runar-rust/runar-ffi)
- Crate exposes a single library `runar_ffi` with type `cdylib, staticlib` and depends on `runar-keys`, `runar-transporter`, `runar-common`, `runar-schemas`.
- Implemented exports (subset):
  - Memory/error: `rn_free`, `rn_string_free`, `RnError`.
  - Keys lifecycle + state: `rn_keys_new/free`, `rn_keys_node_get_public_key`, `rn_keys_node_get_node_id`, CSR/CA flow (`rn_keys_node_generate_csr`, `rn_keys_mobile_process_setup_token`, `rn_keys_node_install_certificate`), state import/export (`rn_keys_node_export_state`, `rn_keys_node_import_state`, `rn_keys_mobile_export_state`, `rn_keys_mobile_import_state`).
  - Transport construct/free: `rn_transport_new_with_keys`, `rn_transport_free`.
- Specified but not yet implemented (per DESIGN.md):
  - Transport lifecycle: `rn_transport_start/stop/local_addr`.
  - Connectivity/messaging: `rn_transport_connect_peer/disconnect_peer/is_connected/request/publish/complete_request/update_local_node_info`.
  - Events: `rn_transport_poll_event` (and optional callback registration).
  - Optional envelope helpers: `rn_keys_encrypt_with_envelope`, `rn_keys_decrypt_envelope`.

### Rust Node (runar-rust/runar-node)
- `NodeConfig` carries config including serialized `NodeKeyManagerState` (bytes). `Node::new` deserializes keys, constructs `ServiceRegistry`, label resolver, and registers `$registry` and `$keys` internal services.
- Node orchestrates: service registration, request routing, event publishing, discovery, and transport integration via `runar_transporter::NetworkTransport`.

### Rust Transporter (runar-rust/runar-transporter)
- QUIC transport with strict TLS defaults, configurable timeouts, message size limits, and address iteration. Discovery providers with lifecycle management. A pre-FFI checklist exists to harden API/impl.

### Swift libraries
- `swift-common`: `RunarLogger` and `NodeId` utilities.
- `swift-serializer`: `AnyValue`, `EnvelopeEncryption`, protocols `EnvelopeCrypto` and `LabelResolver`, `SerializationContext`. Currently bridges `MobileKeyManager: EnvelopeCrypto` (to be replaced by an FFI-backed keystore).
CLARIFICATION.. `swift-serializer`: `AnyValue`, `EnvelopeEncryption`, protocols `EnvelopeCrypto` and `LabelResolver`,  and possibel others..m shudl remain in swift.. as these all support swift proper semantics and APIS>. just the actual enctyption and keys managemetn will be done via FFI.. so the  AnyValue is the hey interface is through that we we serialize and deserialized which includes enctyption and decryptoin for types anotated with encryptoin.
---

## Target architecture

### Components
- Rust `runar_ffi` (one crate, one ABI)
  - Owns keys and transport; exposes opaque handles `FfiKeysHandle`, `FfiTransportHandle` and C ABI functions.
  - Complex values exchanged as canonical CBOR; returned buffers freed with `rn_free`/`rn_string_free`.
  - Event delivery via polling API returning CBOR-encoded events.
- Swift `swift-ffi` package
  - Imports `runar_ffi` header; provides safe Swift wrappers converting `Data`/`String` to C types and mapping `RnError` to `Error`.
  - Swift wrappers for keys and transport; provides `FFIKeyStore: EnvelopeCrypto` for serializer.
- Swift `swift-node` package
  - Reimplements Node control-plane in Swift using `swift-serializer` for payloads and `swift-ffi` for keys/transport.
  - Local service registry, event subscriptions, request routing mirroring `runar-node`.
  - Internal `$registry` and `$keys` services.

### Data flow overview
- App creates `SwiftNodeConfig` (Swift analog of `NodeConfig`).
- App restores Node keys by decrypting persisted CBOR state with iOS Keychain AES-GCM, then passes plaintext CBOR into `swift-ffi` → `rn_keys_node_import_state`.
- `swift-ffi` constructs transport via `rn_transport_new_with_keys(options_cbor)` when networking is enabled.
- `swift-node` runs a background event loop that polls `rn_transport_poll_event` and dispatches to the registry.
- Requests/publishes from Swift services are serialized using `swift-serializer` and sent via `rn_transport_request/publish`; responses/events are deserialized and delivered to handlers.

### Concurrency
- A single runtime inside `runar_ffi` (Tokio) runs transport/discovery. Swift uses async/await/Dispatch; FFI interactions are on background queues.
- Events use polling to avoid foreign-thread callbacks into Swift initially. Callback path can be added later.

---

## FFI interface mapping

### Handles and errors
- Opaque pointers are wrapped by Swift classes managing `UnsafeMutableRawPointer`.
- All FFI functions return `Int32`. Non-zero populates `RnError { code, message }`. Swift converts to `Error` and frees `message` with `rn_string_free`.
- For returned buffers (`uint8_t* + len`, or `char* + len`), Swift copies into `Data`/`String` then calls `rn_free`/`rn_string_free`.

### Keys APIs (existing)
- Construct/destroy: `rn_keys_new` / `rn_keys_free`.
- Identity: `rn_keys_node_get_public_key`, `rn_keys_node_get_node_id`.
- CSR/cert flow: `rn_keys_node_generate_csr`, `rn_keys_mobile_process_setup_token`, `rn_keys_node_install_certificate`.
- State: `rn_keys_node_export_state`, `rn_keys_node_import_state`, and mobile variants.
- Optional: envelope encrypt/decrypt helpers (recommended to implement in FFI for Swift serializer integration).

### Transport APIs (to implement in FFI)
- Construct/destroy: `rn_transport_new_with_keys` / `rn_transport_free`.
- Lifecycle: `rn_transport_start`, `rn_transport_stop`, `rn_transport_local_addr`.
- Connectivity: `rn_transport_connect_peer`, `rn_transport_disconnect_peer`, `rn_transport_is_connected`.
- Messaging: `rn_transport_request`, `rn_transport_publish`, `rn_transport_complete_request`, `rn_transport_update_local_node_info`.
- Events: `rn_transport_poll_event` returns CBOR-encoded events: `PeerConnected`, `PeerDisconnected`, `RequestReceived`, `ResponseReceived`.

### CBOR message contracts
- Options (`QuicTransportOptionsFFI`): `{ v, bind_addr, handshake_timeout_ms, open_stream_timeout_ms, max_message_size, log_level, ... }`.
- Events carry node IDs, correlation IDs, payload bytes, and profile public keys as needed.
- Keys contracts (`SetupToken`, `NodeCertificateMessage`, `Node/Mobile state`) as CBOR.

---

## Swift Node design

### API surface
- `public struct SwiftNodeConfig` (analog of Rust `NodeConfig`):
  - `defaultNetworkId: String`
  - `networkIds: [String]`
  - `networking: SwiftNetworkConfig?` (bind addr, timeouts, max message size)
  - `logging: LoggingConfig?`
  - `keyManagerStateCBOR: Data` (plaintext CBOR provided by host after Keychain decryption)
  - `requestTimeoutMs: UInt64`
- `public final class SwiftNode`:
  - `init(config: SwiftNodeConfig)`
  - `func addService(_ service: AbstractService) async throws`
  - `func start() async throws` / `func stop() async`
  - Requests: `func request(_ path: String, payload: AnyValue?) async throws -> AnyValue`
  - Events: `func publish(_ topic: String, data: AnyValue?) async throws`
  - Subscriptions: `func subscribe(_ topic: String, options: EventRegistrationOptions?, callback: @escaping (EventContext, AnyValue?) async -> Void) async throws -> String`, `func unsubscribe(_ id: String) async throws`
  - One-shot: `func on(_ topic: String, options: OnOptions?) -> Task<AnyValue?>`
- Internal services:
  - `$registry`: `services/list`, `services/{service_path}`, `services/{service_path}/state`, `pause`, `resume`.
  - `$keys`: `ensure_symmetric_key` delegated to a `KeysDelegate` backed by `FFIKeys`.

### Internals
- `ServiceRegistry` in Swift mirrors Rust: local/remote handlers, event subscribers, service state, unsubscribe flows, wildcard matching.
- Event loop task pulls from `pollEvent`, decodes CBOR, updates remote services, routes requests/responses.
- Remote services: Swift proxies that send over transport with correlation IDs and serialize via `AnyValue`.
- Serialization: `SerializationContext` uses `FFIKeyStore` and a configurable `LabelResolver`.

---

## Serialization and keystore integration

- Replace `MobileKeyManager: EnvelopeCrypto` usage with `FFIKeyStore: EnvelopeCrypto` implemented in `swift-ffi`.
- Preferred: implement `rn_keys_encrypt_with_envelope` and `rn_keys_decrypt_envelope` in Rust FFI so Swift `AnyValue` can call into Rust for envelope crypto.
- `SerializationContext` remains unchanged in Swift.

---

## iOS/macOS secure persistence for keys

- Host encrypts/decrypts plaintext CBOR state with a device-bound symmetric key (Keychain AES-GCM). Store only ciphertext.
- First run: `rn_keys_new` → CSR → CA flow → `rn_keys_node_export_state` → encrypt → persist.
- Subsequent runs: decrypt → `rn_keys_node_import_state`.

---

## Build, packaging, and linking

- Rust: build `runar_ffi` for Apple targets; produce a single `.xcframework` and a C header via `cbindgen`.
- `swift-ffi` SwiftPM package:
  - Binary target referencing the `.xcframework` (preferred) or build-script that compiles Rust.
  - Module map for the C header. Swift wrappers provide ergonomic APIs.
- `swift-node` SwiftPM package depends on `swift-ffi`, `swift-common`, `swift-serializer`, `swift-serializer-macros`.

---

## Tasks and milestones

### A. Complete Rust FFI (runar-rust/runar-ffi)
- [ ] Implement transport lifecycle APIs: `rn_transport_start`, `rn_transport_stop`, `rn_transport_local_addr`.
- [ ] Implement connectivity/messaging: `rn_transport_connect_peer`, `rn_transport_disconnect_peer`, `rn_transport_is_connected`, `rn_transport_request`, `rn_transport_publish`, `rn_transport_complete_request`, `rn_transport_update_local_node_info`.
- [ ] Implement event system and `rn_transport_poll_event` returning canonical CBOR per DESIGN.
- [ ] Add optional envelope helpers: `rn_keys_encrypt_with_envelope`, `rn_keys_decrypt_envelope`.
- [ ] Add panic guards and unify error codes; ensure no unwinding across FFI.
- [ ] Ensure `cbindgen.toml` covers all types/functions; document ABI stability.
- [ ] CI: build Apple slices; produce `.xcframework` + header.

### B. Create Swift FFI package (runar-swift/swift-ffi)
- [ ] Add Swift Package `swift-ffi` with a binary target pointing to `runar_ffi.xcframework` and header.
- [ ] Keys wrapper:
  - `final class FFIKeys { init(), deinit, var nodeId: String, var publicKey: Data, func generateCSR() -> Data, func installCertificate(_ ncm: Data) }`
  - State: `exportState() -> Data`, `importState(_ state: Data)`, plus mobile state helpers as needed.
- [ ] Transport wrapper:
  - `final class FFITransport { init(keys: FFIKeys, options: TransportOptions), start/stop, localAddr, connectPeer, disconnectPeer, isConnected, request, publish, completeRequest, updateLocalNodeInfo }`
  - Polling: `pollEvent() -> Data?` with decode helpers.
- [ ] Implement `FFIKeyStore: EnvelopeCrypto` calling the new FFI encrypt/decrypt helpers.
- [ ] Error mapping: convert `RnError` to Swift `Error`, free all allocations.
- [ ] Unit tests: conversions, memory ownership, CSR/cert flow using Rust mobile CA.

### C. Implement Swift Node (runar-swift/swift-node)
- [ ] Package skeleton with dependency on `swift-ffi`, `swift-common`, `swift-serializer`, `swift-serializer-macros`.
- [ ] Implement Swift `ServiceRegistry` (local/remote actions, subscriptions, state, unsubscribe, wildcard matching).
- [ ] Implement `SwiftNodeConfig` and `SwiftNode` lifecycle.
- [ ] Event loop: read `pollEvent`, dispatch `PeerConnected/Disconnected`, `RequestReceived/ResponseReceived`.
- [ ] `$registry` service parity (list/info/state, pause/resume).
- [ ] `$keys` service parity (`ensure_symmetric_key`).
- [ ] Remote service proxies and round-robin load balancing.
- [ ] Serialization integration with `FFIKeyStore` and `LabelResolver`.
- [ ] Tests for local-only and networked flows.

### D. Samples and docs
- [ ] Example app: CSR flow, Keychain persistence, local service.
- [ ] Example: two macOS nodes discovering and communicating.
- [ ] Docs: building Rust FFI, integrating XCFramework, using `swift-node` APIs.

### E. Quality gates
- [ ] Lint/format: Rust `cargo clippy --all-targets --all-features -- -D warnings`; `cargo test --all`. SwiftLint as needed.
- [ ] Thread-safety: polling-only events initially; document threading model.
- [ ] Memory: verify zero leaks with Instruments; always free buffers.
- [ ] ABI/smoke tests across iOS sim/device and macOS.

---

## Risks and mitigations
- Mobile discovery constraints: iOS restricts UDP multicast and background activity. Make discovery optional; allow manual bootstrap; consider platform-native mDNS in Swift calling `connect_peer`.
- Runtime ownership: Swift async vs Rust Tokio. Keep Rust runtime fully internal; use polling; no cross-runtime futures.
- Crypto boundary: Prefer envelope crypto entirely in Rust via FFI helpers to avoid divergence.
- CBOR compatibility: Maintain canonical encoding; add cross-tests Rust↔Swift for events/options.
- Packaging complexity: Automate `.xcframework` builds in CI; pin Rust toolchain.

---

## Open questions
- Add callback-based events (macOS) in addition to polling?
- Host-provided logging callback into Swift vs transporter’s `with_logger_from_node_id`?
- Minimum discovery API surface over FFI vs native Swift mDNS?

---

## Acceptance criteria
- `swift-ffi` wraps finalized `runar_ffi` ABI; functions present and tested.
- `swift-node` can:
  - Initialize with restored keys, start networking, and publish/subscribe locally.
  - Connect to a peer, send request, receive response using `AnyValue` serialization.
  - Enumerate services via `$registry` and manage service states.
- Secure persistence flow with Keychain AES-GCM.
- CI builds `.xcframework` and Swift packages; example app runs on macOS/iOS sim.

---

## Planned repo layout
- `runar-rust/runar-ffi`: unified FFI crate; outputs `runar_ffi.xcframework` + header.
- `runar-swift/swift-ffi`: Swift wrappers around `runar_ffi`.
- `runar-swift/swift-node`: new Swift Node library.
- Existing Swift modules remain; only keystore bridge changes.

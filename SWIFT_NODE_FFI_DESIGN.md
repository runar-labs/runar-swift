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
- Implemented exports (verified from runar_ffi.h):
  - Memory/error: `rn_free`, `rn_string_free`, `rn_last_error`, `rn_set_log_level`.
  - Keys lifecycle + state: `rn_keys_new/free`, `rn_keys_node_get_public_key`, `rn_keys_node_get_node_id`, CSR/CA flow (`rn_keys_node_generate_csr`, `rn_keys_mobile_process_setup_token`, `rn_keys_node_install_certificate`), state import/export (`rn_keys_node_export_state`, `rn_keys_node_import_state`, `rn_keys_mobile_export_state`, `rn_keys_mobile_import_state`), persistence (`rn_keys_set_persistence_dir`, `rn_keys_enable_auto_persist`, `rn_keys_wipe_persistence`, `rn_keys_flush_state`).
  - Envelope helpers: `rn_keys_encrypt_with_envelope`, `rn_keys_decrypt_envelope`, `rn_keys_encrypt_local_data`, `rn_keys_decrypt_local_data`, `rn_keys_encrypt_message_for_mobile`, `rn_keys_decrypt_message_from_mobile`, `rn_keys_encrypt_for_public_key`, `rn_keys_encrypt_for_network`, `rn_keys_decrypt_network_data`.
  - Mobile-specific: `rn_keys_mobile_initialize_user_root_key`, `rn_keys_mobile_derive_user_profile_key`, `rn_keys_mobile_install_network_public_key`, `rn_keys_mobile_generate_network_data_key`, `rn_keys_mobile_get_network_public_key`, `rn_keys_mobile_create_network_key_message`, `rn_keys_node_install_network_key`.
  - Keystore caps/state: `rn_keys_get_keystore_caps`, `rn_keys_node_get_keystore_state`, `rn_keys_mobile_get_keystore_state`.
  - Device keystore registration: `rn_keys_register_apple_device_keystore`, `rn_keys_register_linux_device_keystore`.
  - Mapping/info setters: `rn_keys_set_label_mapping`, `rn_keys_set_local_node_info`.
  - Transport construct/free: `rn_transport_new_with_keys`, `rn_transport_free`.
  - Transport lifecycle: `rn_transport_start/stop/local_addr`.
  - Connectivity/messaging: `rn_transport_connect_peer/disconnect_peer/is_connected/request/publish/complete_request/update_local_node_info`.
  - Events: `rn_transport_poll_event`.
- Discovery: `rn_discovery_new_with_multicast`, `rn_discovery_free`, `rn_discovery_init`, `rn_discovery_bind_events_to_transport`, `rn_discovery_start_announcing`, `rn_discovery_stop_announcing`, `rn_discovery_shutdown`, `rn_discovery_update_local_peer_info`.
- All functions from the original design are implemented, plus additional mobile/device keystore APIs and discovery subsystem.

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

We have updated the key managner data flow.. here is the latest version:
### Objectives

- Ensure upper layers never receive raw key manager state bytes.
- Move state persistence, encryption, and loading into the Rust layer.
- Provide a minimal lifecycle probe so upper layers know whether to run first-time setup.

### Lifecycle redesign (encrypted on-device persistence)

- On startup, upper layer (eç.g. swift) calls a new keystore state probe:
  - `rn_keys_mobile_get_keystore_state(keys, int32_t* out_state, err)`
  - `rn_keys_node_get_keystore_state(keys, int32_t* out_state, err)`
  - `out_state` values:
    - `0` = empty / not initialized
    - `1` = initialized / ready

- Semantics:
  - When called, Rust checks for a persisted state on disk. If present, it decrypts it using a device-keystore-bound key and loads it in-memory, then returns `1`.
  - If not present, returns `0` and does not create any state yet.

- Persistence directory:
  - New setter: `rn_keys_set_persistence_dir(keys, const char* dir, err)`
  - If not set, default per platform:
    - iOS/Android: app-private data dir
    - Linux/macOS: XDG data dir or `$HOME/.local/share/runar`/`$HOME/Library/Application Support/runar`

- Explicit wipe (for dev/testing):
  - `rn_keys_wipe_persistence(keys, err)`

### Immediate removals (no backwards compatibility)

- Remove from header and implementation (not used by any upper layer):
  - `rn_keys_node_export_state`, `rn_keys_node_import_state`
  - `rn_keys_mobile_export_state`, `rn_keys_mobile_import_state`
  - Tests/examples must switch to lifecycle probes and device-keystore-backed persistence.

### New API surface (additions)

Mobile (user) operations:

```c
int32_t rn_keys_mobile_initialize_user_root_key(void *keys, struct RNAPIRnError *err);
int32_t rn_keys_mobile_derive_user_profile_key(void *keys,
                                               const char *label,
                                               uint8_t **out_pk,
                                               size_t *out_len,
                                               struct RNAPIRnError *err);
int32_t rn_keys_mobile_install_network_public_key(void *keys,
                                                  const uint8_t *network_pub,
                                                  size_t len,
                                                  struct RNAPIRnError *err);
```



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

### Keys APIs (all implemented in FFI)
- Construct/destroy: `rn_keys_new` / `rn_keys_free`.
- Identity: `rn_keys_node_get_public_key`, `rn_keys_node_get_node_id`.
- CSR/cert flow: `rn_keys_node_generate_csr`, `rn_keys_mobile_process_setup_token`, `rn_keys_node_install_certificate`.
- State: `rn_keys_node_export_state`, `rn_keys_node_import_state`, and mobile variants.
- Envelope encrypt/decrypt helpers: `rn_keys_encrypt_with_envelope`, `rn_keys_decrypt_envelope` (for Swift serializer integration).
- Mobile/device: `rn_keys_mobile_initialize_user_root_key`, `rn_keys_mobile_derive_user_profile_key`, etc.
- Persistence and caps: `rn_keys_set_persistence_dir`, `rn_keys_enable_auto_persist`, `rn_keys_wipe_persistence`, `rn_keys_flush_state`, `rn_keys_get_keystore_caps`, `rn_keys_node_get_keystore_state`, `rn_keys_mobile_get_keystore_state`.
- Device registration: `rn_keys_register_apple_device_keystore`, `rn_keys_register_linux_device_keystore`.
- Setters: `rn_keys_set_label_mapping`, `rn_keys_set_local_node_info`.

### Transport APIs (all implemented in FFI)
- Construct/destroy: `rn_transport_new_with_keys` / `rn_transport_free`.
- Lifecycle: `rn_transport_start`, `rn_transport_stop`, `rn_transport_local_addr`.
- Connectivity: `rn_transport_connect_peer`, `rn_transport_disconnect_peer`, `rn_transport_is_connected`.
- Messaging: `rn_transport_request`, `rn_transport_publish`, `rn_transport_complete_request`, `rn_transport_update_local_node_info`.
- Events: `rn_transport_poll_event` returns CBOR-encoded events: `PeerConnected`, `PeerDisconnected`, `RequestReceived`, `ResponseReceived`.

### Discovery APIs (all implemented in FFI)
- Construct/free: `rn_discovery_new_with_multicast` / `rn_discovery_free`.
- Lifecycle: `rn_discovery_init`, `rn_discovery_bind_events_to_transport`, `rn_discovery_start_announcing`, `rn_discovery_stop_announcing`, `rn_discovery_shutdown`.
- Updates: `rn_discovery_update_local_peer_info`.

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

## Build, packaging, and linking

- Rust: build `runar_ffi` for Apple targets; produce a single `.xcframework` and a C header via `cbindgen`.
- `swift-ffi` SwiftPM package:
  - Binary target referencing the `.xcframework` (preferred) or build-script that compiles Rust.
  - Module map for the C header. Swift wrappers provide ergonomic APIs.
- `swift-node` SwiftPM package depends on `swift-ffi`, `swift-common`, `swift-serializer`, `swift-serializer-macros`.

---

## Tasks and milestones

### A. Complete Rust FFI (runar-rust/runar-ffi)
- [x] Implement transport lifecycle APIs: `rn_transport_start`, `rn_transport_stop`, `rn_transport_local_addr`.
- [x] Implement connectivity/messaging: `rn_transport_connect_peer`, `rn_transport_disconnect_peer`, `rn_transport_is_connected`, `rn_transport_request`, `rn_transport_publish`, `rn_transport_complete_request`, `rn_transport_update_local_node_info`.
- [x] Implement event system and `rn_transport_poll_event` returning canonical CBOR per DESIGN.
- [x] Add optional envelope helpers: `rn_keys_encrypt_with_envelope`, `rn_keys_decrypt_envelope`.
- [x] Add panic guards and unify error codes; ensure no unwinding across FFI.
- [x] Ensure `cbindgen.toml` covers all types/functions; document ABI stability.
- [ ] CI: build Apple slices; produce `.xcframework` + header.
- [x] Implement additional APIs: discovery subsystem, mobile/device keystore registration, persistence, keystore caps/state.

### B. Create Swift FFI package (runar-swift/swift-ffi)
- [x] Add Swift Package `swift-ffi` with C module importing `runar_ffi.h` and Swift target `RunarFFI`.
- [x] Keys wrapper:
  - Implemented `FFIKeys` with `init()/deinit`, `nodeId()`, `publicKey()`, `generateCSR()`, `processSetupToken(_:)`, `installCertificate(_:)`, `exportState()`, `importState(_:)`, plus setters like `setLabelMapping` and `setLocalNodeInfo`.
- [x] Transport wrapper skeleton:
  - Implemented `FFITransport` with `init(keys:optionsCBOR:)`, `start/stop`, `localAddr`, `connectPeer`, `disconnectPeer`, `isConnected`, `request`, `publish`, `completeRequest`, `pollEvent`, `updateLocalNodeInfo`.
  - Options passed as CBOR `Data` to match FFI contract.
- [ ] Implement `FFIKeyStore: EnvelopeCrypto` calling the new FFI encrypt/decrypt helpers (pending: CBOR encoding/decoding for EnvelopeEncryptedData).
- [x] Error mapping tests and memory ownership tests (basic in KeysTests; expand for transport/envelope).

Progress/decisions:
- We import the Rust header via a C target `CRunarFFI` and link locally to the Rust debug library for dev. For CI, we will switch to an `.xcframework` binary target.
- Wrappers return `Data`/`String` and free all FFI-owned buffers via `rn_free`/`rn_string_free` immediately after copying. Errors are mapped to `FFIError`.
- Transport options are passed as canonical CBOR using `CodableCBOREncoder` to match Rust’s expected schema.

### C. Implement Swift Node (runar-swift/swift-node)
- [ ] Package skeleton with dependency on `swift-ffi`, `swift-common`, `swift-serializer`, `swift-serializer-macros`.
- [ ] Implement Swift `ServiceRegistry` (local/remote actions, subscriptions, state, unsubscribe, wildcard matching).
- [ ] Implement `SwiftNodeConfig` and `SwiftNode` lifecycle.
- [x] Event loop: read `pollEvent`, dispatch `PeerConnected/Disconnected`, `RequestReceived/ResponseReceived`.
- [x] `$registry` service parity (list/info/state, pause/resume).
- [ ] `$keys` service parity (`ensure_symmetric_key`).
- [ ] Remote service proxies and round-robin load balancing.
- [ ] Serialization integration with `FFIKeyStore` and `LabelResolver`.
- [x] Tests for local-only flows and an initial network stub test that exercises request round-trip through the event loop.

Progress/decisions:
- The Swift Node mirrors Rust behavior: publish is broadcast (no peer selection). Requests select a destination peer using round-robin per service when available; otherwise, they are sent without a destination.
- Peer events use Rust’s CBOR keys (`type`, `peer_node_id`, etc.). On `PeerConnected`, we proactively query the peer’s `$registry/services/list` to register remote services.
- We added a `NodeTransport` protocol and an internal initializer for dependency injection in tests (no hacks in production code paths).

Planned:
- Expose connect/disconnect/isConnected/updateLocalNodeInfo to public API (already present) and add integration tests when FFI transport is fully available on macOS.

### D. Samples and docs
- [ ] Example app: CSR flow, Keychain persistence, local service.
- [ ] Example: two macOS nodes discovering and communicating.
- [ ] Docs: building Rust FFI, integrating XCFramework, using `swift-node` APIs.

### New: Swift Test Utilities (swift-test-utils)
- A lightweight package mirroring Rust `runar-test-utils` that helps tests build realistic setups:
  - `TestFixtures.createKeyManagerWithCert()` builds a CA and a node `FFIKeys`, runs CSR/CA flow, installs cert.
  - CBOR encoders for `PeerInfo`, `NodeInfo`, and transport options matching Rust schemas.
- Used to bootstrap transporter/network tests once FFI transport is enabled in CI.

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

## Swift service macros (ergonomics)

We will add Swift macros to mirror the ergonomics of `runar-rust/runar-macros`, so services can be defined declaratively without manually implementing `AbstractService` each time.

### Goals
- Eliminate boilerplate by generating `AbstractService` conformance, metadata, and handler registration.
- Provide `@Service`, `@Action`, `@Publish`, and `@Subscribe` macros analogous to Rust `#[service]`, `#[action]`, `#[publish]`, and `#[subscribe]`.
- Integrate with `SwiftNode` so generated code registers actions/subscriptions during `initService` automatically.
- Leverage `RunarSerializer.AnyValue` for param/result serialization and Swift macro diagnostics for better developer feedback.

### Proposed package
- New SwiftPM package: `swift-node-macros`
  - Product: `SwiftNodeMacros`
  - Dependencies: `swift-syntax` (matching Swift toolchain), `SwiftCBOR` (optional for compile-time schema helpers), and `swift-common` for common names.
  - Emits macros:
    - `@Service(name: String, path: String, description: String, version: String)`
    - `@Action(_ name: String? = nil, path: String? = nil)`
    - `@Publish(path: String)` — attaches to an `@Action` to auto-publish the action result to a topic
    - `@Subscribe(path: String)` — defines event handlers as methods

### Behavior mapping
- `@Service` on a type:
  - Synthesizes `AbstractService` conformance with computed properties `name`, `version`, `path`, `description`.
  - Generates `initService(_:)` to register all `@Action` methods and `@Subscribe` callbacks on the provided `LifecycleContext` (using `registerAction` / `subscribe`).
  - Optionally generates `start(_:)`/`stop(_:)` no-ops.
- `@Action` on an instance method:
  - Generates a wrapper `ActionHandler` bridging from `AnyValue` parameters to strongly typed parameters (positional or map-like), using `RunarSerializer` conversions.
  - Registers under derived path: `servicePath/actionName` unless overridden by `path` or full `network:service/action` format.
- `@Publish` on an `@Action` method:
  - After the action returns a result `R`, generates `context.publish(topic, AnyValue.struct(R))` (or appropriate category) with topic resolution rules identical to Rust macros.
- `@Subscribe` on an instance method:
  - Generates an event subscription that deserializes payload to the method’s parameter type, then invokes the method with an `EventContext`.

### Example (Swift) based on Rust test `runar-macros/tests/simple_service_macros.rs`
```swift
import SwiftNode
import SwiftNodeMacros
import RunarSerializer

@Service(
  name: "Test Service Name",
  path: "math",
  description: "Test Service Description",
  version: "0.0.1"
)
struct TestService {
  var store: [String: AnyValue] = [:]

  @Action
  func echo(_ message: String) async throws -> String {
    message
  }

  @Publish(path: "added")
  @Action
  func add(_ a: Double, _ b: Double, _ ctx: RequestContext) async throws -> Double {
    ctx.debug("Adding \(a) + \(b)")
    return a + b
  }

  @Action(path: "multiply_numbers")
  func multiply(_ a: Double, _ b: Double, _ ctx: RequestContext) async throws -> Double {
    a * b
  }

  @Subscribe(path: "math/added")
  func onAdded(_ total: Double, _ ctx: EventContext) async {
    ctx.debug("on_added: \(total)")
    // update store, etc.
  }
}

// Usage
let node = SwiftNode(config: .init(defaultNetworkId: "net"))
try await node.addService(TestService())
try await node.start()
let result = try await node.request("math/add", payload: AnyValue.map([
  "a": AnyValue.primitive(10.0),
  "b": AnyValue.primitive(5.0)
]))
```

### Design notes
- Parameter decoding strategy: if the action has a single non-context parameter and the payload is a map with a matching key, accept both direct and map-wrapped forms (gateway ergonomics). For multi-arg, accept map with keys matching parameter names.
- Return value encoding: primitives → `AnyValue.primitive`, structs → `AnyValue.struct`, lists/maps → corresponding categories. If already `AnyValue`, pass through.
- Topic resolution: identical to Rust macros: relative paths resolved to `network:service/path`.
- Metadata: macros generate `ActionMetadata` and optionally `FieldSchema` stubs for discovery.

### Tasks
- [ ] Create `swift-node-macros` package with macro scaffolding.
- [ ] Implement `@Service` to synthesize `AbstractService` and registration in `initService(_:)`.
- [ ] Implement `@Action` wrapper generation with parameter/return bridging to `AnyValue`.
- [ ] Implement `@Publish` to auto-publish action results.
- [ ] Implement `@Subscribe` to generate event subscriptions and payload decoding.
- [ ] Add tests mirroring Rust macro tests (echo/add/multiply/divide, complex structs, publish/subscribe).
- [ ] Docs with examples and migration guide.


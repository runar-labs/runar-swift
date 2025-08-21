## Swift ↔ Rust Runar Node Alignment

This document tracks a line-by-line alignment between the Swift Node (`swift-node`) and the Rust Node public API and the expected dataflow/behavior. It identifies mismatches and enumerates concrete tasks to converge Swift behavior to match Rust 1:1 (public API, runtime sequence, internal events, and business rules).

### Scope
- Public API surface: methods, signatures, return types, error semantics.
- Internal control-plane flow: startup/shutdown ordering, service registration, discovery, registry topics, and event retention semantics (include_past, retained events).
- Transport-facing behaviors: request/response, publish/subscribe, peer lifecycle events.

### References
- Rust (authoritative): runar-node (public API, services, registry internals)
- Swift: `swift-node/Sources/SwiftNode/SwiftNode.swift`, `ServiceRegistry.swift`, `Contexts.swift`, `Schemas.swift`, tests in `swift-node/Tests`

> Note: Where Rust references are noted, confirmation against the current Rust repo is still required. All mismatches listed here were derived from Swift sources and the previously specified Rust API signatures in conversation.

---

## Rust Node (authoritative) – Public API summary (to confirm against repo)

- `on(&self, topic: impl Into<String>, options: Option<OnOptions>) -> JoinHandle<Result<Option<ArcValue>>>`
- `publish(&self, topic: &str, data: Option<ArcValue>) -> Result<()>`
- `publish_with_options(&self, topic: &str, data: Option<ArcValue>, options: PublishOptions) -> Result<()>`
- `request(&self, path: &str, data: Option<ArcValue>) -> Result<ArcValue>` (or async variant)
- `request_at_peer(&self, path: &str, data: Option<ArcValue>, peer_node_id: &str, timeout: Duration) -> Result<ArcValue>`
- Discovery/peer-management helpers and export/import peer info
- `$registry` internal service topics:
  - `$registry/services/list`
  - `$registry/services/{service_path}`
  - `$registry/services/{service_path}/state`
  - `$registry/services/{service_path}/pause`
  - `$registry/services/{service_path}/resume`
  - `$registry/peer/{peer_id}/discovered`
  - `$registry/peer/{peer_id}/disconnected`

Behavior highlights to mirror:
- Internal service registration completes before transport start.
- After transport starts, discovery and peer events begin; internal `$registry` topics must be available beforehand.
- `include_past` relies on retained events; internal peer events should be retained long enough to be consumed after subscription.

---

## Swift Node – Current Public API (from `SwiftNode.swift`)

Public surface:
- `@MainActor init(config: SwiftNodeConfig, logger: RunarLogger)`
- `@MainActor init(config: SwiftNodeConfig, keys: FFIKeys, logger: RunarLogger)`
- `@MainActor func addService(_ service: AbstractService) async throws`
- `@MainActor func start() async throws`
- `@MainActor func stop() async`
- `@MainActor func publish(_ topic: String, data: AnyValue?) async throws`
- `@MainActor func publish(_ topic: String, data: AnyValue?, retainFor: TimeInterval?) async throws`
- `@MainActor func publishWithOptions(_ topic: String, data: AnyValue?, options: PublishOptions) async throws`
- `@MainActor func subscribe(_ topic: String, options: EventRegistrationOptions? = nil, callback: @escaping EventHandler) async throws -> String`
- `@MainActor func on(_ topic: String, options: OnOptions? = nil) -> JoinHandle<Result<AnyValue?, Error>>`
- `@MainActor func request(_ path: String, payload: AnyValue?) async throws -> AnyValue`
- `@MainActor func requestToPeer(_ path: String, payload: AnyValue?, peerNodeId: String, timeoutMs: UInt64? = nil) async throws -> AnyValue`
- `@MainActor func connectPeer(_ peerInfoCBOR: Data) throws`
- `@MainActor func disconnectPeer(_ peerNodeId: String) throws`
- `@MainActor func isConnected(_ peerNodeId: String) throws -> Bool`
- `@MainActor func exportPeerInfoCBOR() throws -> Data`

Internal `$registry` actions registered in `registerInternalServices()`:
- `services/list`
- `services/{service_path}`
- `services/{service_path}/state`
- `services/{service_path}/pause`
- `services/{service_path}/resume`

Internal peer events (emitted in `handleTransportEvent`):
- `$registry/peer/{peer_id}/discovered` (retained for 10s by default)
- `$registry/peer/{peer_id}/disconnected` (retained for 10s by default)

### Service lifecycle (Swift)
- `addService`:
  - Always registers metadata.
  - Calls `service.initService(context)`.
  - If node is already started, immediately calls `service.start(context)` and marks service state as `running`.
  - If node not started, stores instance; start will occur during `node.start()`.
- `start`:
  - Registers internal `$registry` services first.
  - Starts any pending local services via `service.start(context)`; only then marks service state as `running`.
  - Starts transport and discovery, then sets the node to started.
- Local request routing checks the target service state; if not `running`, the request is rejected.

Runtime sequence (current Swift):
1) Register internal services (always before transport).
2) For each added-but-not-started service: call `start()` and mark `running` after success.
3) Start transport; bind discovery to transport; start event loop.
4) Emit internal peer events and handle service registry synchronization.

Retained events:
- `publishWithOptions` supports `retainFor`; retained events are stored as `AnyValue` to preserve zero-copy locally.
- Default retained deque per topic capped at 16 entries (subject to alignment with Rust policy).

---

## Identified mismatches and gaps

1) Public API names and signatures
- Match: `on`, `publish`, `publishWithOptions`, `request`, `requestToPeer` equivalents exist.
- Return types: Swift uses `AnyValue` and `JoinHandle<Result<AnyValue?, Error>>`, matching Rust semantics (`Option<ArcValue>`). Confirm exact error mapping parity (Rust `Result` error types vs Swift `Error`).
- Task: Verify all public method names and parameters exactly match Rust names (case/wording). If Swift naming must differ for Swift idioms, document mapping explicitly.

2) Internal startup sequence
- Rust: Internal services registered before transport start; then discovery and peer events begin.
- Swift: Implemented; also enforces service `start` gating before marking `running`.
- Task: Add explicit unit test asserting internal `$registry` registration finishes before transport start and that services are unavailable before `start` completes.

3) `$registry` peer events and retention
- Rust: Tests wait on `$registry/peer/{id}/discovered` with include_past. Requires retention.
- Swift: Emits discovered/disconnected and retains 10s. Confirm Rust retention ttl; align TTL or make configurable.
- Task: Add configurable retention TTL for internal events to mirror Rust default.

4) `$registry/services/list` query fallback on connect
- Swift queries peer for `services/list` when not included in connect event, but timeouts show in tests.
- Rust behavior to confirm: does node eagerly advertise service list on connect, or should Swift cache/refresh differently?
- Task: Align service discovery advertisement on connect; ensure the transport discovery path provides services list or remove blocking reliance on immediate query.

5) Event retention cap
- Swift caps retained events per topic at 16. Rust behavior may be TTL-only.
- Task: Confirm Rust policy; if TTL-only, remove hard cap or make it match Rust.

6) Error codes and timeouts
- Swift uses generic NSError codes (408 for timeouts). Rust likely uses structured error enums.
- Task: Map common error categories into a typed Swift error enum mirroring Rust error taxonomy.

7) JoinHandle semantics
- Swift `JoinHandle.value()` returns on main actor and maps raw bytes -> `AnyValue` on main actor; Rust returns `Result<Option<ArcValue>>`.
- Task: Confirm cancellation semantics and ensure parity with Rust (cancellation behavior and drop semantics).

8) Discovery binding
- Swift binds FFIDiscovery to the transport after transport start. Confirm Rust’s discovery startup order and options.
- Task: Ensure discovery lifecycle matches Rust (announcing/stop/shutdown hooks).

9) Schema parity
- Swift’s `RegistryServiceMetadata` structure should match Rust exactly (field names/types).
- Task: Cross-check schema field-by-field against Rust definitions.

10) `$registry` topic naming completeness
- Ensure all Rust `$registry` topics exist in Swift (including any additional health/metrics endpoints if present in Rust).
- Task: Audit topics and add missing ones.

---

## Alignment Plan – Actionable Tasks

1) Public API verification (Blocking)
- [ ] Extract Rust public API (signatures, docs) for Node; compare one-by-one with Swift methods
- [ ] Adjust Swift method names/signatures to match exactly (or document explicit mapping table)

2) Internal services and startup ordering (Blocking)
- [ ] Add explicit unit test asserting internal `$registry` registration finishes before transport start
- [ ] Verify that services are not callable until `start()` completes; add test using a stateful service
- [ ] Ensure discovery only starts after transport; verify ordering with logs/tests

3) `$registry` peer events (High)
- [ ] Confirm Rust retention TTL for `$registry/peer/*` events; align Swift default
- [ ] Add configuration knob for internal-event retention TTL (match Rust if configurable)
- [ ] Verify include_past delivers retained events reliably (add test using `on(...)`)

4) Service advertisement and remote registry sync (High)
- [ ] Confirm Rust behavior for initial peer services propagation
- [ ] If Rust advertises services on connect, mirror in Swift (transport/discovery path) and remove fragile immediate query fallback
- [ ] Add test waiting on `$registry/peer/{id}/discovered` then `$registry/services/list` successful query

5) Retention policy parity (Medium)
- [ ] Remove or align the hard cap (16) to Rust policy; switch to TTL-only or match count

6) Error taxonomy (Medium)
- [ ] Define Swift error enum mapping Rust node errors (timeout, not found, network, decode, etc.)
- [ ] Replace generic `NSError` uses with typed errors; update tests

7) JoinHandle parity (Medium)
- [ ] Confirm cancel semantics vs Rust `JoinHandle`; add tests for cancellation mid-wait

8) Discovery lifecycle (Medium)
- [ ] Cross-check start/stop/shutdown flows; align FFIDiscovery usage with Rust discovery state machine

9) Schema parity (Medium)
- [ ] Compare `RegistryServiceMetadata`, `LocalServiceState`, network config structs with Rust; align naming and fields

10) `$registry` topic completeness (Medium)
- [ ] Audit against Rust set; add any missing topics/handlers

11) Documentation
- [ ] Keep this alignment document updated per change; link to specific commits in Swift/Rust for traceability

---

## Current Swift changes addressing parity (implemented)

- Constrained `SwiftNode` and `ServiceRegistry` to `@MainActor`; kept AnyValue decoding on main actor to avoid cross-actor issues.
- Implemented `on(_:options:) -> JoinHandle<Result<AnyValue?, Error>>` following Rust semantics; `includePast` supported via retained events.
- Implemented `$registry` internal service topics and peer lifecycle topics (`discovered`/`disconnected`), with retention for includePast.
- Ensured internal services register before transport startup; discovery binds after transport start.
- Enforced service lifecycle: `initService` on add, `start` either during `node.start()` or immediately if node is already started; service is only marked running after `start` returns, and local routing is gated on running state.

---

## Open Questions (need Rust confirmation)

1) Exact error types and codes returned by Rust Node for timeouts, missing handlers, and network errors
2) Retention TTL and count semantics for internal events (and whether caps exist)
3) Expected contents (payload) of `$registry/peer/{id}/discovered` and `$registry/peer/{id}/disconnected` (currently Swift sends null)
4) Whether Rust advertises services on connect or expects explicit fetch; best practice for sync timing

---

## Next Steps

1) Pull the latest Rust Node repo; run a diff of public APIs and internal `$registry` topics
2) Update Swift API and internal sequences per mismatches found; check in tests mirroring Rust’s integration tests
3) Keep this document as the single source of truth for alignment status


Unrelate to RUST but very important issue to solve

I noticed another issue.. that mnight be quyic to fix..  Circular Dependencies Blocking CI
swift-ffi ↔ swift-test-utils (circular dependency)
swift-ffi ↔ swift-serializer (circular dependency)  lprob because of tsts is my guess...   in swift-ffi lets move these tests out perjaps to a test only pacikage.. .. since  swift-test-utils  do need the ffi and also serialiser also need the ffi.. this way external test pakca can depends on all it needs and nothgn depend son the rtest package..
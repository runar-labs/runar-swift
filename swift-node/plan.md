Detailed Plan:

## PHASE 1: Core Node Structure (Local-First)

### 1.1 NodeConfig for Local-Only Mode
**Current Issues:**
- Swift `SwiftNodeConfig` is simplified compared to Rust `NodeConfig`
- Missing critical fields for local operation
- Network config structure doesn't match Rust `NetworkConfig`

**Required Changes for Local Phase:**
- Replace `SwiftNodeConfig` with `NodeConfig` matching Rust structure
- Add `label_resolver_config: LabelResolverConfig` (REQUIRED field)
- Add `logging_config: Option<LoggingConfig>`
- Add `network_config: Option<NetworkConfig>` (can be None for local-only)
- Add builder pattern methods: `with_logging_config()`, `with_network_config()`, etc.
- Support local-only mode (network_config = None)

### 1.2 Node Struct Core Fields (Local-First)
**Current Issues:**
- Missing core fields present in Rust Node
- Field types and organization don't match
- Missing proper concurrency primitives

**Required Additions for Local Phase:**
```swift
// Core fields needed for local operation:
- node_id: String
- network_id: String
- config: Arc<NodeConfig>
- service_registry: Arc<ServiceRegistry>
- logger: Arc<Logger>
- running: AtomicBool
- supports_networking: Bool
- system_label_config: Arc<LabelResolverConfig>
- service_tasks: Arc<RwLock<[ServiceTask]>>
- local_node_info: Arc<RwLock<NodeInfo>>
- retained_events: Arc<RetainedEventsMap>
- retained_index: Arc<RwLock<PathTrie<String>>>

// Network fields (add in Phase 6):
- network_transport: Arc<RwLock<Option<NetworkTransport>>>
- remote_node_info: Arc<DashMap<String, NodeInfo>>
- discovery_seen_times: Arc<DashMap<String, Instant>>
- network_discovery_providers: Arc<RwLock<Option<[NodeDiscovery]>>>
- load_balancer: Arc<RwLock<LoadBalancingStrategy>>
- label_resolver_cache: Arc<ResolverCache>
- registry_version: Arc<AtomicI64>
- keys_manager: Arc<RwLock<NodeKeyManager>>
```

### 1.4 Swift 6 Concurrency Baseline (Non-Negotiable)
- Use @MainActor isolation for `Node` and `ServiceRegistry` to replace Rust's `Arc<RwLock<...>>` for coordinator types. No `NSLock`.
- Use `ShardedConcurrentMap<Key, Value>` (actor-based) for DashMap equivalents where Value is Sendable and accessed concurrently.
- Do not store non-Sendable values (e.g., service instances) inside `ShardedConcurrentMap`. Keep them on the main actor.
- Replace lock-based round-robin with an actor-based `RoundRobinLoadBalancer` (async `selectHandler`).
- Implement a per-node `ResolverCache` actor (capacity + TTL). No shared/global caches.
- All transport/discovery protocols are async-only and owned/used on the main actor.

### 1.5 Node.new Initialization (Must Match Rust Intent)
- Initialize deterministically (no placeholders):
  - `load_balancer`: new `RoundRobinLoadBalancer()`
  - `label_resolver_cache`: new per-node `ResolverCache(capacity: 1000, ttl=300s)`
  - `registry_version`: `0` (Int64)
  - `remote_node_info`: `ShardedConcurrentMap<String, NodeInfo>()`
  - `discovery_seen_times`: `ShardedConcurrentMap<String, Date>()`
  - `retained_events`: map topic → `RetainedDeque` actor (see Phase 3)
  - `retained_index`: empty `PathTrie<String>`
- Extract `keysManager` from config, validate presence, compute `nodeId` from public key.
- Register internal services (`RegistryService`, `KeysService`) with real registration, no mocks.

## PHASE 2: Local Service Registry (Core Local Functionality)

### 2.1 Service Registration and Management
**Current Issues:**
- Current ServiceRegistry is simplified and doesn't match Rust
- Missing proper service lifecycle state management
- No service metadata tracking

**Required Local Implementation:**
- Implement exact Rust ServiceRegistry structure for local services only
- Add `local_services: Arc<RwLock<PathTrie<Arc<ServiceEntry>>>>`
- Add `local_service_states: Arc<DashMap<String, ServiceState>>`
- Add `local_action_handlers: Arc<RwLock<PathTrie<LocalActionEntryValue>>>`
- Implement service registration, lookup, and state management
- Add service metadata tracking and introspection

### 2.3 Swift 6 Implementation Guidance (Critical)
- ServiceRegistry is `@MainActor`. All its state is main-actor protected (no `NSLock`, no `DispatchQueue`).
- Use these structures:
  - `localActionHandlers: PathTrie<(ActionHandler, TopicPath, ActionMetadata?)>` (tuple matches Rust)
  - `localServices: PathTrie<ServiceEntry>` and `localServicesList: [TopicPath: ServiceEntry]` on the main actor (do not store services in concurrent maps).
  - `localServiceStates: ShardedConcurrentMap<String, ServiceState>` and `remoteServiceStates` as needed.
  - `subscriptionIdToTopicPath` and `subscriptionIdToServiceTopicPath`: `ShardedConcurrentMap<String, TopicPath>`.
- Action registration must always populate `ActionMetadata` like Rust (name, description, schemas optional).
- Request handling resolves path via `PathTrie` and invokes handler with a `RequestContext`.

### 2.2 Local Action Handling
**Current Issues:**
- Action registration and routing is simplified
- Missing proper parameter extraction and validation
- No action metadata management

**Required Local Implementation:**
- Implement `LocalActionEntryValue` structure matching Rust
- Add proper action registration with parameter extraction
- Implement action routing and parameter validation
- Add action metadata tracking and introspection
- Support path parameters and wildcard matching

## PHASE 3: Local Event System (Publish/Subscribe)

### 3.1 Local Event Subscription Management
**Current Issues:**
- Simplified subscription system
- Missing proper subscription metadata management
- No wildcard pattern support

**Required Local Implementation:**
- Implement `SubscriptionVec` structure for local subscriptions only
- Add `event_subscriptions: Arc<RwLock<PathTrie<SubscriptionVec>>>`
- Add `subscription_id_to_topic_path: Arc<DashMap<String, TopicPath>>`
- Implement proper subscription ID management and cleanup
- Add subscription metadata and introspection methods
- Support wildcard pattern matching for subscriptions

### 3.3 Actor-Based Retained Deque (Design and APIs)
- Rust types:
  - `type RetainedDeque = VecDeque<(Instant, Option<ArcValue>)>`
  - `type RetainedEventsMap = DashMap<String, RetainedDeque>`
- Swift 6 equivalents:
  - `public struct RetainedEventEntry: Sendable { timestamp: Date; data: AnyValue? }`
  - `public actor RetainedDeque`:
    - Storage: `private var entries: [RetainedEventEntry] = []`
    - Config: `capacity: Int`, `ttlSeconds: TimeInterval`
    - APIs:
      - `append(_ entry: RetainedEventEntry)`
      - `append(timestamp: Date = Date(), data: AnyValue?)`
      - `pruneExpired(now: Date = Date())`
      - `getLatest(limit: Int) -> [RetainedEventEntry]`
      - `snapshot() -> [RetainedEventEntry]`
    - Behavior: prune on append; enforce capacity by dropping oldest.
  - `typealias RetainedEventsMap = ShardedConcurrentMap<String, RetainedDeque>` (keys = exact topics).

### 3.4 Wiring Retained Events into Publish/Subscribe
- `ServiceRegistry` remains `@MainActor` with `PathTrie<SubscriptionVec>`.
- Publish flow (local-only Phase 1):
  - Parse `TopicPath` (fail fast on invalid).
  - If `retain` or `retainFor` set:
    - TTL = `retainFor ?? defaultTTLFromConfig`.
    - Obtain `RetainedDeque` from `retained_events` (create if missing with capacity/ttl).
    - `await deque.append(timestamp: Date(), data: payload)`.
  - Notify subscribers for the exact topic.
- Include-past on subscribe (optional for Phase 1):
  - If `includePast` window is specified, fetch retained entries within window and deliver before live events.
- Wildcards:
  - Track exact topics in `retained_index: PathTrie<String>` to support future wildcard lookups.

### 3.5 Error Handling and Determinism
- No fallbacks. Invalid `TopicPath` → deterministic error/skip.
- If deque creation fails (invalid config), fail fast with a clear error.

## PHASE 4: Local Service Lifecycle and Task Management

### 4.1 Service Lifecycle Management
**Current Issues:**
- Missing proper service lifecycle state management
- No service task tracking
- Missing service error handling

**Required Local Implementation:**
- Add `service_tasks: Arc<RwLock<[ServiceTask]>>`
- Implement proper service task lifecycle
- Add service error handling and recovery
- Implement service state transitions and validation
- Add service health monitoring and reporting

### 4.3 Swift 6 Guidance
- Lifecycle transitions happen on `@MainActor` in services and registry.
- `ServiceTask` storage is a main-actor array; expose read-only snapshots as needed.
- Do not capture services across threads; all cross-boundary calls are `async` and main-actor confined.

## PHASE 5: Local Testing & Validation

### 5.1 Port Rust Local Tests
**Required Implementation:**
- `test_node_create()`
- `test_node_add_service()`
- `test_node_request()`
- `test_node_events()`
- `test_local_event_dispatch_multiple_subscribers()`
- `test_math_service_plus_external_subscription()`
- `test_node_event_metadata_registration()`
- `test_node_lifecycle()`

### 5.2 Local Test Validation
**Required Implementation:**
- Ensure all local tests pass without networking dependencies
- Validate local service actions work correctly
- Validate local event dispatch works with multiple subscribers
- Validate service registry metadata is correct
- Validate node lifecycle (start/stop) works properly
- Add performance tests for local operations

### 5.3 Test Design Details (No Mocks)
- Node: create with real `NodeKeyManager`, verify `nodeId`, `isRunning` transitions.
- ServiceRegistry: register a real test service; verify actions and `ActionMetadata`.
- Events: publish live-only vs. retained; includePast behavior; multiple subscribers.
- RetainedDeque: capacity and TTL enforcement tests.

## PHASE 6: Network Integration (Remote Features)

### 6.1 Transport and Discovery Integration
**Current Issues:**
- Basic discovery integration exists but incomplete
- Missing proper discovery provider management
- No discovery event handling

**Required Implementation:**
- Add transports, discovery providers, peer info, discovery timing, etc.
- Implement proper discovery event handling
- Add discovery configuration and provider management

### 6.3 Swift 6 Preparation (Do Not Implement Yet in Phase 1)
- Protocols must be async-first (`start/stop/send/publish/...` are `async throws`).
- Ownership on `@MainActor`; internal I/O happens under the hood in their own actors/threads.
- No placeholders: keep unimplemented but throwing explicit errors until Phase 6.

## PHASE 7: Remote Services and Load Balancing

### 7.1 Load Balancing Strategy
**Required Implementation:**
- Add `load_balancer`
- Implement `LoadBalancingStrategy`
- Add `RoundRobinLoadBalancer`
- Add strategy selection

### 7.3 Swift 6 Guidance
- Use an actor-based `RoundRobinLoadBalancer` with `selectHandler(handlers:) async -> String?`.
- Keep strategy references on `@MainActor` in `Node`.

## PHASE 8: Label Resolver and Serialization Integration

### 8.1 Label Resolver System Integration
**Current Status:**
- ✅ Complete label resolver system exists in `swift-serializer`

**Required Node Integration:**
- Add `system_label_config` to Node
- Add `label_resolver_cache` to Node
- Initialize label resolver from NodeConfig in Node constructor
- Pass label resolver to SerializationContext for all serialization operations

### 8.3 Swift 6 Guidance
- Implement `ResolverCache` as a per-node actor with `(capacity, ttlSeconds)`.
- Key by `(LabelResolverConfig + userProfilePublicKeys)`; prune expired entries on access.
- Create resolver via `LabelResolver.createContextResolver(systemConfig:userProfilePublicKeys:)`.
- Build `SerializationContext` on demand for actions/events with proper resolver and keystore.

## PHASE 9: Remote Testing & Validation

### 6.1 Service Task Management
**Current Issues:**
- Missing proper service task tracking
- No service lifecycle state management
- Missing service error handling

**Required Implementation:**
- Add `service_tasks`
- Implement proper service task lifecycle
- Add service error handling and recovery
- Implement service state transitions and validation

### 6.2 Service Registry Integration
**Current Issues:**
- Service registry doesn't properly integrate with node lifecycle
- Missing service metadata management
- No proper service introspection

**Required Implementation:**
- Integrate service registry with node lifecycle
- Add service metadata management
- Implement service introspection and debugging
- Add service health monitoring and reporting

## PHASE 7: Testing and Validation

### 7.1 Test Suite Alignment
**Current Issues:**
- Tests are basic and don't match Rust test coverage
- Missing integration tests
- No performance tests

**Required Implementation:**
- Port all Rust tests to Swift
- Add comprehensive integration tests
- Add performance and stress tests
- Add concurrency and race condition tests

### 7.2 Test Data and Vectors
**Current Status:**
- ✅ Comprehensive test vector system exists in `swift-ffi`
- ✅ Cross-language CBOR validation between Swift and Rust
- ✅ Test vector generation

### 7.3 Common Pitfalls and How We Avoid Them
- Do not use `NSLock` or ad-hoc `DispatchQueue` in place of Rust `DashMap`/`RwLock`. Use `@MainActor` for coordinators and `ShardedConcurrentMap` for concurrent maps.
- Never store `AbstractService` or any non-Sendable in `ShardedConcurrentMap`. Keep services on `@MainActor` only.
- No `@unchecked Sendable` anywhere.
- Avoid duplicate schema/metadata types across packages. Prefer a single canonical definition and provide conversion helpers if wire types differ.
- Fail early on invalid configuration—no hidden fallbacks.

## IMPLEMENTATION ORDER

### LOCAL FEATURES FIRST (Prove Core Functionality)

1. **Phase 1**: Core Node Structure (NodeConfig, basic Node fields)
2. **Phase 2**: Local Service Registry (service registration, local actions, service metadata)
3. **Phase 3**: Local Event System (publish/subscribe, retained events, local event dispatch)
4. **Phase 4**: Local Service Lifecycle (service initialization, start/stop, error handling)
5. **Phase 5**: Local Testing & Validation (port Rust local tests, validate local functionality)

### REMOTE FEATURES SECOND (Add Networking)

6. **Phase 6**: Network Integration (transport, discovery, peer management)
7. **Phase 7**: Remote Services (load balancing, remote service calls, peer registry)
8. **Phase 8**: Label Resolver Integration (leverage existing swift-serializer)
9. **Phase 9**: Remote Testing & Validation (network tests, cross-language validation)
10. **Phase 10**: Documentation and Examples

### LOCAL-FIRST TESTING STRATEGY

**Phase 5 Local Tests (Based on Rust Tests):**
- `test_node_create()`
- `test_node_add_service()`
- `test_node_request()`
- `test_node_events()`
- `test_local_event_dispatch_multiple_subscribers()`
- `test_math_service_plus_external_subscription()`
- `test_node_event_metadata_registration()`
- `test_node_lifecycle()`

**Success Criteria for Local Phase:**
- [ ] All local Rust tests ported and passing in Swift
- [ ] Local service actions work correctly
- [ ] Local event dispatch works with multiple subscribers
- [ ] Service registry metadata is correct
- [ ] Node lifecycle (start/stop) works properly
- [ ] No networking dependencies in local tests

### Additional Acceptance for Phase 1 (Swift 6)
- [ ] No `NSLock` used in `Node` or `ServiceRegistry`
- [ ] No `@unchecked Sendable` anywhere
- [ ] `RoundRobinLoadBalancer` implemented as an actor
- [ ] `ResolverCache` implemented as a per-node actor
- [ ] Retained events implemented with `RetainedDeque` actor and integrated into publish

## EXISTING INFRASTRUCTURE TO LEVERAGE

### Swift-Serializer Package (Complete)
- ✅ `LabelResolver` and `LabelResolverConfig` for dynamic label resolution
- ✅ `SerializationContext` with keystore and resolver integration
- ✅ `SerializationRegistry` for type registration and wire name management
- ✅ `AnyValue` system for type-erased serialization
- ✅ Full encryption/decryption support with `CommonKeyManager`
- ✅ CBOR serialization with proper type handling

### Swift-FFI Package (Complete)
- ✅ `FFIKeys` and `FFITransport` for network operations
- ✅ `CommonKeyManager` for cryptographic operations
- ✅ Complete FFI type definitions and CBOR compatibility
- ✅ Cross-language validation infrastructure

### Test Infrastructure (Complete)
- ✅ `FFITypesCrossValidationTests.swift` for CBOR compatibility
- ✅ Rust validation script (`validate_swift_vectors.rs`)
- ✅ Test vector generation and validation
- ✅ Round-trip serialization testing

### Swift-Common Package (Complete)
- ✅ `TopicPath` and `PathTrie` for routing
- ✅ `RunarLogger` for logging
- ✅ Error handling utilities

## SUCCESS CRITERIA

- [ ] 100% API alignment with Rust Node implementation
- [ ] All Rust tests ported and passing in Swift
- [ ] Performance characteristics match Rust implementation
- [ ] Memory management and concurrency safety verified
- [ ] Cross-language compatibility validated using existing test infrastructure
- [ ] Proper integration with existing swift-serializer and swift-ffi packages
- [ ] Documentation and examples complete
- [ ] Code quality standards met
- [ ] Integration tests passing
- [ ] No regressions in existing functionality

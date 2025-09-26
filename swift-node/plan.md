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

### 1.3 ServiceRegistry Local Implementation
**Current Issues:**
- Current ServiceRegistry is a simplified version
- Missing critical Rust functionality for local services
- Data structures don't match Rust implementation

**Required Local-First Implementation:**
- Implement exact Rust ServiceRegistry structure for local services
- Add `local_action_handlers: Arc<RwLock<PathTrie<LocalActionEntryValue>>>`
- Add `event_subscriptions: Arc<RwLock<PathTrie<SubscriptionVec>>>`
- Add `subscription_id_to_topic_path: Arc<DashMap<String, TopicPath>>`
- Add `local_services: Arc<RwLock<PathTrie<Arc<ServiceEntry>>>>`
- Add `local_service_states: Arc<DashMap<String, ServiceState>>`
- Implement all local service methods from Rust ServiceRegistry

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

### 3.2 Local Event Publishing and Dispatch
**Current Issues:**
- Basic event publishing exists but doesn't match Rust
- Missing proper event dispatch to multiple subscribers
- No event retention system

**Required Local Implementation:**
- Implement proper event publishing to local subscribers
- Add support for multiple subscribers to same topic
- Implement event dispatch with proper error handling
- Add event retention system for local events
- Support event filtering and wildcard matching

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

### 4.2 Service Registry Integration
**Current Issues:**
- Service registry doesn't properly integrate with node lifecycle
- Missing service metadata management
- No proper service introspection

**Required Local Implementation:**
- Integrate service registry with node lifecycle
- Add proper service metadata management
- Implement service introspection and debugging
- Add service health monitoring and reporting
- Support service pause/resume functionality

## PHASE 5: Local Testing & Validation

### 5.1 Port Rust Local Tests
**Required Implementation:**
- Port `test_node_create()` - Basic node creation without networking
- Port `test_node_add_service()` - Service registration and lifecycle
- Port `test_node_request()` - Local service action calls (MathService add operation)
- Port `test_node_events()` - Local event publish/subscribe
- Port `test_local_event_dispatch_multiple_subscribers()` - Multiple subscribers
- Port `test_math_service_plus_external_subscription()` - Service + external events
- Port `test_node_event_metadata_registration()` - Service registry metadata
- Port `test_node_lifecycle()` - Start/stop lifecycle

### 5.2 Local Test Validation
**Required Implementation:**
- Ensure all local tests pass without networking dependencies
- Validate local service actions work correctly
- Validate local event dispatch works with multiple subscribers
- Validate service registry metadata is correct
- Validate node lifecycle (start/stop) works properly
- Add performance tests for local operations

## PHASE 6: Network Integration (Remote Features)

### 6.1 Transport and Discovery Integration
**Current Issues:**
- Basic discovery integration exists but incomplete
- Missing proper discovery provider management
- No discovery event handling

**Required Implementation:**
- Add `network_transport: Arc<RwLock<Option<NetworkTransport>>>`
- Add `network_discovery_providers: Arc<RwLock<Option<[NodeDiscovery]>>>`
- Add `remote_node_info: Arc<DashMap<String, NodeInfo>>`
- Add `discovery_seen_times: Arc<DashMap<String, Instant>>`
- Implement proper discovery event handling
- Add discovery configuration and provider management

### 6.2 Peer Management
**Current Issues:**
- Missing centralized peer directory
- No proper peer state management
- Missing discovery event debouncing

**Required Implementation:**
- Implement peer connection/disconnection lifecycle
- Add peer metadata management and updates
- Implement discovery debouncing and filtering
- Add peer health monitoring and reporting

## PHASE 7: Remote Services and Load Balancing

### 7.1 Load Balancing Strategy
**Current Issues:**
- Missing load balancing for remote services
- No strategy pattern implementation
- Round-robin logic is hardcoded

**Required Implementation:**
- Add `load_balancer: Arc<RwLock<LoadBalancingStrategy>>`
- Implement `LoadBalancingStrategy` protocol
- Add `RoundRobinLoadBalancer` implementation
- Add load balancing configuration and strategy selection

### 7.2 Remote Service Management
**Current Issues:**
- Basic remote service tracking exists
- Missing proper remote service lifecycle
- No remote service state management

**Required Implementation:**
- Add `remote_services: Arc<RwLock<PathTrie<Arc<RemoteService>>>>>`
- Add `remote_service_states: Arc<DashMap<String, ServiceState>>`
- Implement remote service lifecycle management
- Add remote service metadata and introspection

## PHASE 8: Label Resolver and Serialization Integration

### 8.1 Label Resolver System Integration
**Current Status:**
- ✅ Complete label resolver system exists in `swift-serializer` package
- ✅ `LabelResolver` with proper configuration and validation
- ✅ `LabelResolverConfig` with static label mappings
- ✅ `SerializationContext` with keystore and resolver integration

**Required Node Integration:**
- Add `system_label_config: Arc<LabelResolverConfig>` to Node
- Add `label_resolver_cache: Arc<ResolverCache>` to Node
- Initialize label resolver from NodeConfig in Node constructor
- Pass label resolver to SerializationContext for all serialization operations

### 8.2 Serialization Context Management
**Current Status:**
- ✅ Complete serialization system exists in `swift-serializer` package
- ✅ `SerializationContext` with keystore, resolver, networkId, and profilePublicKey
- ✅ `SerializationRegistry` for type registration and wire name management
- ✅ Full encryption/decryption support with `CommonKeyManager` integration

**Required Node Integration:**
- Initialize `SerializationContext` with proper keystore and resolver
- Use existing `SerializationRegistry.shared` for type management
- Integrate serialization context creation in request/response handling
- Leverage existing `AnyValue` serialization system

## PHASE 9: Remote Testing & Validation

### 6.1 Service Task Management
**Current Issues:**
- Missing proper service task tracking
- No service lifecycle state management
- Missing service error handling

**Required Implementation:**
- Add `service_tasks: Arc<RwLock<[ServiceTask]>>`
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
- Add proper service metadata management
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
- ✅ Comprehensive test vector system exists in `swift-ffi` package
- ✅ Cross-language CBOR validation between Swift and Rust (`FFITypesCrossValidationTests.swift`)
- ✅ Rust validation script (`validate_swift_vectors.rs`) for serializer compatibility
- ✅ Test vector generation for FFI types and serializer types
- ✅ Round-trip serialization validation

**Required Node-Specific Implementation:**
- Port Rust Node tests to Swift Node tests
- Add Node-specific test vectors for service registry, peer management, etc.
- Extend existing cross-validation to include Node-specific types
- Add integration tests using existing test vector infrastructure
- Add edge case and error condition tests for Node functionality

## PHASE 8: Documentation and Examples

### 8.1 API Documentation
**Current Issues:**
- Missing comprehensive API documentation
- No usage examples
- Missing migration guide

**Required Implementation:**
- Add comprehensive API documentation
- Create usage examples and tutorials
- Add migration guide from current implementation
- Add performance and best practices guide

### 8.2 Code Quality and Standards
**Current Issues:**
- Code doesn't follow all Swift best practices
- Missing proper error handling patterns
- No consistent naming conventions

**Required Implementation:**
- Apply Swift coding standards throughout
- Implement consistent error handling patterns
- Add proper logging and debugging support
- Add code quality metrics and monitoring

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
- `test_node_create()` - Basic node creation without networking
- `test_node_add_service()` - Service registration and lifecycle
- `test_node_request()` - Local service action calls (e.g., MathService add operation)
- `test_node_events()` - Local event publish/subscribe
- `test_local_event_dispatch_multiple_subscribers()` - Multiple subscribers to same topic
- `test_math_service_plus_external_subscription()` - Service + external event subscription
- `test_node_event_metadata_registration()` - Service registry metadata
- `test_node_lifecycle()` - Start/stop lifecycle

**Success Criteria for Local Phase:**
- [ ] All local Rust tests ported and passing in Swift
- [ ] Local service actions work correctly
- [ ] Local event dispatch works with multiple subscribers
- [ ] Service registry metadata is correct
- [ ] Node lifecycle (start/stop) works properly
- [ ] No networking dependencies in local tests

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

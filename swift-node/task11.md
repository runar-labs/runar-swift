GOAL - Address all the issues in this review - fix all issues in Swift IMPL

DO IT one by one methodicxally. IF U FIND ISSUES STOP AND ASK FOR INPUT. DO NOT SKIP ANYTHING, DO  NO HACK. DO NOT TAKE ANOTHER PPROACH OR TRY TO SIMPLIFY OR CHAGNE THINGS..

SWIFT must be 100% aligned to RUST. EVETY STEP. EVERY RULES> EVERY CONDITIONS> MUST ALIGN.

LANGUAGE DIFFERENCES (ACCEPTABLE):
Rust: Arc::new(NodeKeyManagerWrapper(...)) vs Swift: keysManager directly ✅
Rust: HashMap::new() vs Swift: [:] dictionary literal ✅
Rust: ArcValue::new_primitive() vs Swift: AnyValue.primitive() ✅
Rust: response.serialize(Some(&context)) vs Swift: response.serialize(context: context) ✅


## **DETAILED METHOD-BY-METHOD ANALYSIS: Swift vs Rust Node Implementation**

### **1. NODE CONSTRUCTOR COMPARISON**

#### **Rust Node::new() (lines 619-706):**
```rust
pub async fn new(config: NodeConfig) -> Result<Self> {
    // Apply logging configuration
    if let Some(logging_config) = &config.logging_config {
        logging_config.apply();
    } else {
        let default_config = LoggingConfig::default_info();
        default_config.apply();
    }

    // Clone fields before moving config
    let default_network_id = config.default_network_id.clone();
    let networking_enabled = config.network_config.is_some();

    let mut network_ids = config.network_ids.clone();
    network_ids.push(default_network_id.clone());
    network_ids.dedup();

    let logger = Arc::new(Logger::new_root(Component::Node));
    let service_registry = Arc::new(ServiceRegistry::new(logger.clone()));

    // Extract the key manager from config
    let keys_manager = config.key_manager.clone()
        .ok_or_else(|| anyhow::anyhow!("Failed to load node credentials."))?;

    let Some(node_public_key) = keys_manager.read().unwrap().get_node_public_key() else {
        return Err(anyhow::anyhow!("Node public key not available"));
    };
    let node_id = compact_id(&node_public_key);
    logger.set_context(node_id.clone());

    log_info!(logger, "Successfully loaded existing node credentials.");

    let local_node_info = NodeInfo {
        node_public_key: node_public_key.clone(),
        network_ids: network_ids.clone(),
        addresses: vec![],
        node_metadata: NodeMetadata {
            services: vec![],
            subscriptions: vec![],
        },
        version: 0,
    };

    let node = Self {
        local_node_info: Arc::new(RwLock::new(local_node_info)),
        debounce_notify_task: std::sync::Arc::new(Mutex::new(None)),
        network_id: default_network_id,
        network_ids,
        node_id,
        node_public_key,
        config: Arc::new(config.clone()),
        logger: logger.clone(),
        service_registry,
        remote_node_info: Arc::new(DashMap::new()),
        discovery_seen_times: Arc::new(DashMap::new()),
        running: AtomicBool::new(false),
        supports_networking: networking_enabled,
        network_transport: Arc::new(RwLock::new(None)),
        network_discovery_providers: Arc::new(RwLock::new(None)),
        load_balancer: Arc::new(RwLock::new(RoundRobinLoadBalancer::new())),
        system_label_config: Arc::new(config.label_resolver_config),
        label_resolver_cache: Arc::new(ResolverCache::new(1000, Duration::from_secs(300))),
        registry_version: Arc::new(AtomicI64::new(0)),
        keys_manager,
        service_tasks: Arc::new(RwLock::new(Vec::new())),
        retained_events: Arc::new(RetainedEventsMap::new()),
        retained_index: Arc::new(RwLock::new(PathTrie::new())),
    };

    // Register the registry service
    let registry_service = RegistryService::new(
        logger.clone(),
        Arc::new(node.clone()) as Arc<dyn RegistryDelegate>,
    );
    node.add_service(registry_service).await?;

    let keys_service = KeysService::new(
        logger.clone(),
        Arc::new(node.clone()) as Arc<dyn KeysDelegate>,
    );
    node.add_service(keys_service).await?;

    Ok(node)
}
```

#### **Swift Node.new() (lines 1412-1480):**
```swift
public static func new(config: NodeConfig) async throws -> Node {
    // Clone fields before moving config
    let defaultNetworkId = config.defaultNetworkId
    let networkingEnabled = config.networkConfig != nil

    var networkIds = config.networkIds
    networkIds.append(defaultNetworkId)
    networkIds = Array(Set(networkIds)) // Remove duplicates

    let logger = RunarLogger.root(component: .node, config: config.loggerConfig)
    let serviceRegistry = ServiceRegistry(logger: logger, nodeDelegate: nil) // Will be set after initialization

    // Extract the key manager from config
    guard let keysManager = config.getKeyManager() else {
        throw NodeError.missingKeyManager("Failed to load node credentials.")
    }

    let nodePublicKey = try await keysManager.getNodePublicKey()
    let nodeId = try await keysManager.getCompactId(for: nodePublicKey)
    // logger.setContext(nodeId) // RunarLogger doesn't have setContext method

    logger.trace("Successfully loaded existing node credentials.")

    let localNodeInfo = NodeInfo(
        nodePublicKey: nodePublicKey,
        networkIds: networkIds,
        addresses: [],
        nodeMetadata: NodeMetadata(services: [], subscriptions: []),
        version: 0
    )

    let node = Node(
        debounceTask: nil as Task<Void, Never>?,
        networkId: defaultNetworkId,
        networkIds: networkIds,
        nodeId: nodeId,
        nodePublicKey: nodePublicKey,
        config: config,
        serviceRegistry: serviceRegistry,
        remoteNodeInfo: ShardedConcurrentMap<String, NodeInfo>(),
        discoverySeenTimes: ShardedConcurrentMap<String, Date>(),
        logger: logger,
        running: false,
        supportsNetworking: networkingEnabled,
        networkTransport: nil as NodeTransport?,
        networkDiscoveryProviders: nil as [NodeDiscovery]?,
        loadBalancer: RoundRobinLoadBalancer(),
        systemLabelConfig: config.labelResolverConfig,
        labelResolverCache: ResolverCache(capacity: 1000, ttlSeconds: 300),
        registryVersion: 0,
        keysManager: keysManager,
        serviceTasks: [],
        localNodeInfo: localNodeInfo,
        retainedEvents: ShardedConcurrentMap<String, RetainedDeque>(),
        retainedIndex: PathTrie<String>()
    )

    // Register the registry service
    let registryService = RegistryService(
        logger: logger,
        registryDelegate: node
    )
    try await node.addService(registryService)

    let keysService = KeysService(
        logger: logger,
        nodeDelegate: node
    )
    try await node.addService(keysService)

    return node
}
```

### **✅ CONSTRUCTOR COMPARISON RESULTS:**

| **Aspect** | **Rust** | **Swift** | **Status** |
|---|---|---|---|
| **Logging Setup** | `Logger::new_root(Component::Node)` | `RunarLogger.root(component: .node, config: config.loggerConfig)` | ✅ Language difference |
| **Service Registry** | `Arc::new(ServiceRegistry::new(logger.clone()))` | `ServiceRegistry(logger: logger, nodeDelegate: nil)` | ✅ Language difference |
| **Key Manager** | `config.key_manager.clone().ok_or_else(...)` | `config.getKeyManager()` | ✅ Language difference |
| **Node Public Key** | `keys_manager.read().unwrap().get_node_public_key()` | `keysManager.getNodePublicKey()` | ✅ Language difference |
| **Node ID** | `compact_id(&node_public_key)` | `keysManager.getCompactId(for: nodePublicKey)` | ✅ Language difference |
| **Logger Context** | `logger.set_context(node_id.clone())` | `// logger.setContext(nodeId) // RunarLogger doesn't have setContext method` | ❌ **MISSING** |
| **Network IDs** | `network_ids.dedup()` | `Array(Set(networkIds))` | ✅ Language difference |
| **Data Structures** | `Arc<DashMap<>>`, `Arc<RwLock<>>` | `ShardedConcurrentMap`, actor isolation | ✅ Language difference |
| **Service Registration** | `node.add_service(registry_service).await?` | `node.addService(registryService)` | ✅ Language difference |

### **❌ ISSUE FOUND: Missing Logger Context Setting**

**Rust**: `logger.set_context(node_id.clone());`
**Swift**: `// logger.setContext(nodeId) // missing. we have added the logger.setContext() in swift. so lets use it.

## **2. ADD_SERVICE METHOD COMPARISON**

#### **Rust add_service() (lines 789-894):**
```rust
pub async fn add_service<S: AbstractService + 'static>(&self, mut service: S) -> Result<()> {
    let default_network_id = self.network_id.to_string();
    let service_network_id = match service.network_id() {
        Some(id) => id,
        None => default_network_id.clone(),
    };
    service.set_network_id(service_network_id.clone());

    let service_path = service.path();
    let service_name = service.name();

    log_info!(self.logger, "Adding service '{service_name}' to node using path {service_path}");
    log_debug!(self.logger, "network id {default_network_id}");

    let registry = Arc::clone(&self.service_registry);
    // Create a proper topic path for the service
    let service_topic = match TopicPath::new(service_path, &default_network_id) {
        Ok(tp) => tp,
        Err(e) => {
            log_error!(self.logger, "Failed to create topic path for service name:{service_name} path:{service_path} error:{e}");
            return Err(anyhow!("Failed to create topic path for service {}: {}", service_name, e));
        }
    };

    // Create a lifecycle context for initialization
    let init_context = LifecycleContext::new(
        &service_topic,
        Arc::new(self.clone()), // Node delegate
        Arc::new(self.logger.clone().with_component(Component::Service)),
    );

    // Initialize the service using the context
    if let Err(e) = service.init(init_context).await {
        log_error!(self.logger, "Failed to initialize service: {service_name}, error: {e}");
        registry.update_local_service_state(&service_topic, ServiceState::Error).await?;
        self.publish(
            &format!("$registry/services/{}/state/error", service_topic.service_path()),
            Some(ArcValue::new_primitive(service_topic.as_str().to_string())),
            Some(PublishOptions {
                broadcast: false,
                guaranteed_delivery: false,
                retain_for: Some(Duration::from_secs(10)),
                target: None,
                profile_public_keys: None,
            }),
        ).await?;
        return Err(anyhow!("Failed to initialize service: {e}"));
    }
    registry.update_local_service_state(&service_topic, ServiceState::Initialized).await?;
    self.publish(
        &format!("$registry/services/{}/state/initialized", service_topic.service_path()),
        Some(ArcValue::new_primitive(service_topic.as_str().to_string())),
        Some(PublishOptions {
            broadcast: false,
            guaranteed_delivery: false,
            retain_for: Some(Duration::from_secs(10)),
            target: None,
            profile_public_keys: None,
        }),
    ).await?;
    // Service initialized successfully, create the ServiceEntry and register it
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();

    let service_entry = Arc::new(ServiceEntry {
        service: Arc::new(service),
        service_topic: service_topic.clone(),
        service_state: ServiceState::Initialized,
        registration_time: now,
        last_start_time: None, // Will be set when the service is started
    });
    registry.register_local_service(service_entry.clone()).await?;

    if self.running.load(Ordering::SeqCst) {
        self.start_service(&service_topic, service_entry.as_ref(), true).await;
    }

    Ok(())
}
```

#### **Swift addService() (lines 1744-1823):**
```swift
public func addService(_ service: AbstractService) async throws {
    // Set the service's network ID
    service.setNetworkId(networkId)

    let servicePath = service.path
    let serviceName = service.name

    logger.trace("Adding service '\(serviceName)' to node using path \(servicePath)")

    // Create a proper topic path for the service (matching Rust pattern)
    let serviceTopic = try TopicPath.new(servicePath, defaultNetwork: networkId)

    // Create a lifecycle context for initialization (matching Rust pattern)
    let initContext = LifecycleContext(
        networkId: networkId,
        servicePath: servicePath,
        config: nil,
        logger: logger,
        nodeDelegate: self
    )

    // Initialize the service using the context (matching Rust pattern)
    do {
        try await service.initService(initContext)
    } catch {
        logger.error("Failed to initialize service: \(serviceName), error: \(error)")
        // Update service state to error (matching Rust pattern)
        try await serviceRegistry.updateLocalServiceState(
            servicePath: serviceTopic.rawPath,
            newState: ServiceState.error
        )
        // Publish error event (matching Rust pattern)
        try await publish(
            topic: "$registry/services/\(servicePath)/state/error",
            data: AnyValue.primitive(serviceTopic.rawPath),
            options: PublishOptions(retainFor: 10.0)
        )
        throw NodeError.serviceInitializationFailed("Failed to initialize service: \(error)")
    }

    // Update service state to initialized (matching Rust pattern)
    try await serviceRegistry.updateLocalServiceState(
        servicePath: serviceTopic.rawPath,
        newState: ServiceState.initialized
    )

    // Publish initialized event (matching Rust pattern)
    try await publish(
        topic: "$registry/services/\(servicePath)/state/initialized",
        data: AnyValue.primitive(serviceTopic.rawPath),
        options: PublishOptions(retainFor: 10.0)
    )

    // Service initialized successfully, create the ServiceEntry and register it (matching Rust pattern)
    let now = UInt64(Date().timeIntervalSince1970)

    let serviceEntry = ServiceEntry(
        serviceTopic: serviceTopic,
        service: service,
        state: ServiceState.initialized,
        registrationTime: now,
        lastStartTime: nil // Will be set when the service is started
    )

    // Register the service with the registry (matching Rust pattern)
    try await serviceRegistry.registerLocalService(serviceEntry)
    logger.trace("🔍 Service registered successfully: \(servicePath)")

    // Update the transport with the new NodeInfo if the node is already running
    // If the node is not yet started, the transport will be created with the current NodeInfo when it starts
    if isRunning {
        logger.trace("🔍 SERVICE: Node is running, updating transport with new NodeInfo...")
        await updateTransportNodeInfo()
    } else {
        logger.trace("🔍 SERVICE: Node not yet started, transport will be created with current NodeInfo when started")
    }

    // If the node is already running, start the service immediately (matching Rust pattern)
    if isRunning {
        try await startService(serviceTopic: serviceTopic, serviceEntry: serviceEntry)
    }
}
```

### **✅ ADD_SERVICE METHOD COMPARISON RESULTS:**

| **Aspect** | **Rust** | **Swift** | **Status** |
|---|---|---|---|
| **Network ID Handling** | `match service.network_id() { Some(id) => id, None => default_network_id.clone() }` | `service.setNetworkId(networkId)` | ❌ **MISSING** - Swift doesn't check existing network ID |
| **Logging** | `log_info!` + `log_debug!` | `logger.trace` | ✅ Language difference |
| **Topic Path Creation** | `TopicPath::new(service_path, &default_network_id)` with error handling | `TopicPath.new(servicePath, defaultNetwork: networkId)` | ❌ **MISSING** - Swift doesn't handle TopicPath creation errors |
| **Lifecycle Context** | `LifecycleContext::new(&service_topic, Arc::new(self.clone()), Arc::new(self.logger.clone().with_component(Component::Service)))` | `LifecycleContext(networkId: networkId, servicePath: servicePath, config: nil, logger: logger, nodeDelegate: self)` | ❌ **DIFFERENT** - Different constructor signature |
| **Service Initialization** | `service.init(init_context).await` | `service.initService(initContext)` | ✅ Language difference |
| **Error Handling** | `if let Err(e) = service.init(init_context).await` | `do { try await service.initService(initContext) } catch` | ✅ Language difference |
| **State Updates** | `registry.update_local_service_state(&service_topic, ServiceState::Error).await?` | `serviceRegistry.updateLocalServiceState(servicePath: serviceTopic.rawPath, newState: ServiceState.error)` | ✅ Language difference |
| **Publish Options** | `PublishOptions { broadcast: false, guaranteed_delivery: false, retain_for: Some(Duration::from_secs(10)), target: None, profile_public_keys: None }` | `PublishOptions(retainFor: 10.0)` | ❌ **MISSING** - Swift doesn't set all options |
| **Service Entry Creation** | `Arc::new(ServiceEntry { service: Arc::new(service), service_topic: service_topic.clone(), service_state: ServiceState::Initialized, registration_time: now, last_start_time: None })` | `ServiceEntry(serviceTopic: serviceTopic, service: service, state: ServiceState.initialized, registrationTime: now, lastStartTime: nil)` | ✅ Language difference |
| **Running Check** | `if self.running.load(Ordering::SeqCst)` | `if isRunning` | ✅ Language difference |
| **Service Start** | `self.start_service(&service_topic, service_entry.as_ref(), true).await` | `try await startService(serviceTopic: serviceTopic, serviceEntry: serviceEntry)` | ✅ Language difference |

### **❌ ISSUES FOUND IN ADD_SERVICE METHOD:**

1. **Missing Network ID Check**: Swift doesn't check if service already has a network ID
2. **Missing TopicPath Error Handling**: Swift doesn't handle TopicPath creation errors
3. **Different LifecycleContext Constructor**: Different signature between Rust and Swift
4. **Missing PublishOptions Fields**: Swift doesn't set all the same options as Rust
 
 LEts fix all these issues and make swift align to rust 100%

### **3. START METHOD COMPARISON**

#### **Rust start() (lines 1102-1181):**
```rust
pub async fn start(&self) -> Result<()> {
    log_info!(self.logger, "Starting node...");

    if self.running.load(Ordering::SeqCst) {
        log_warn!(self.logger, "Node already running");
        return Ok(());
    }

    // Get services directly from the registry
    let registry = Arc::clone(&self.service_registry);
    let local_services = registry.get_local_services().await;

    let internal_services = local_services
        .iter()
        .filter(|(_, service_entry)| is_internal_service(service_entry.service.path()))
        .collect::<HashMap<_, _>>();
    let non_internal_services = local_services
        .iter()
        .filter(|(_, service_entry)| !is_internal_service(service_entry.service.path()))
        .collect::<HashMap<_, _>>();

    // start internal services first
    for (service_topic, service_entry) in internal_services {
        self.start_service(service_topic, service_entry, false).await;
    }

    // Start networking if enabled
    if self.supports_networking {
        if let Err(e) = self.start_networking().await {
            log_error!(self.logger, "Failed to start networking components: {e}");
            return Err(e);
        }
    }

    log_info!(self.logger, "Node started successfully - it will start all services now");
    self.running.store(true, Ordering::SeqCst);

    // Start non-internal services in parallel to avoid blocking the loop
    let mut tasks_store = self.service_tasks.write().await;
    let service_start_timeout = Duration::from_secs(30); //TODO MOVE THIS TO A CONFIG
    for (service_topic, service_entry) in non_internal_services {
        let node_clone = Arc::new(self.clone());
        let service_topic_clone = service_topic.clone();
        let service_entry_clone = service_entry.clone();
        let task = spawn(async move {
            log_info!(node_clone.logger, "Starting separate thread to start service: {service_topic_clone}");
            
            // Add timeout to the service start operation
            match timeout(service_start_timeout, node_clone.start_service(&service_topic_clone, &service_entry_clone, true)).await {
                Ok(_) => {
                    log_info!(node_clone.logger, "Service start completed: {service_topic_clone}");
                }
                Err(_) => {
                    log_error!(node_clone.logger, "Service start timed out after 30 seconds: {service_topic_clone}");
                }
            }
        });
        tasks_store.push((service_topic.clone(), task));
    }

    Ok(())
}
```

#### **Swift start() (lines 1900-1922):**
```swift
public func start() async throws {
    logger.trace("Node started networkId=\(networkId)")

    // Start all registered services
    logger.trace("🔍 DEBUG: About to start all local services for networkId: \(networkId)")
    try await serviceRegistry.startAllServices(networkId: networkId)
    logger.trace("🔍 DEBUG: All local services started successfully")

    // Initialize network transport if networking is enabled
    if supportsNetworking {
        try await initializeNetworkTransport()

        // Update the transport with current NodeInfo after it's created
        // This ensures the transport has the latest NodeInfo with all services
        logger.trace("🔍 START: Updating transport with current NodeInfo after creation...")
        await updateTransportNodeInfo()
    }

    // Set the node as running
    running = true

    logger.trace("Node is now running")
}
```

### **❌ MAJOR ISSUES FOUND IN START METHOD:**

| **Aspect** | **Rust** | **Swift** | **Status** |
|---|---|---|---|
| **Already Running Check** | `if self.running.load(Ordering::SeqCst) { log_warn!(self.logger, "Node already running"); return Ok(()); }` | **MISSING** | ❌ **CRITICAL MISSING** |
| **Service Separation** | Separates internal vs non-internal services | `serviceRegistry.startAllServices(networkId: networkId)` | ❌ **MISSING** - No separation |
| **Service Start Order** | Internal services first, then non-internal | All services together | ❌ **WRONG ORDER** |
| **Parallel Service Start** | Non-internal services started in parallel with timeout | Sequential start | ❌ **MISSING** - No parallelization |
| **Service Timeout** | 30-second timeout for service start | No timeout | ❌ **MISSING** - No timeout |
| **Error Handling** | Proper error handling for networking failure | Basic error handling | ❌ **INCOMPLETE** |
| **Running Flag** | Set after networking starts | Set at the end | ❌ **WRONG TIMING** |

This is a **CRITICAL ISSUE** - the Swift start method is missing most of the sophisticated service management logic that Rust has.

 LEts fix all these to have swift align to RUST 100%


### **4. REQUEST METHOD COMPARISON**

#### **Rust request() (lines 2155-2252):**
```rust
pub async fn request<P>(
    &self,
    path: &str,
    payload: Option<P>,
    options: Option<RequestOptions>,
) -> Result<ArcValue>
where
    P: AsArcValue + Send + Sync,
{
    let request_payload_av = payload.map(|p| p.into_arc_value());
    let topic_path = match TopicPath::new(path, &self.network_id) {
        Ok(tp) => tp,
        Err(e) => return Err(anyhow!("Failed to parse topic path: {path} : {e}",)),
    };

    log_debug!(self.logger, "Processing request: {topic_path}");

    // First check local service state - if no state exists, no local service exists
    let service_topic = TopicPath::new_service(&self.network_id, &topic_path.service_path());
    let service_state = self.service_registry.get_local_service_state(&service_topic).await;

    // If service state exists, check if it's running
    if let Some(state) = service_state {
        if state != ServiceState::Running {
            log_debug!(self.logger, "Service {} is in {:?} state, trying remote handlers", topic_path.service_path(), state);
            // Try remote handlers instead
            match self.remote_request(topic_path.as_str(), request_payload_av, options).await {
                Ok(response) => return Ok(response),
                Err(_) => {
                    // Remote request failed - return state-specific error since we know local service exists but is not running
                    return Err(anyhow!("Service is not Running - it is in {} state", state));
                }
            }
        }
    }

    // Service is either running or doesn't exist locally - check for local handler
    if let Some((handler, registration_path)) = self.service_registry.get_local_action_handler(&topic_path).await {
        log_debug!(self.logger, "Executing local handler for: {topic_path}");

        let profile_public_keys = options.map(|o| o.profile_public_keys).unwrap_or_default().unwrap_or_default();

        let mut metadata: HashMap<String, ArcValue> = HashMap::new();
        metadata.insert("node_id".to_string(), ArcValue::new_primitive(self.node_id.clone()));
        metadata.insert("profile_public_keys".to_string(), ArcValue::new_list(profile_public_keys));

        // Create request context
        let mut context = RequestContext::new(&topic_path, Arc::new(self.clone()), metadata, self.logger.clone());

        // Extract parameters using the original registration path
        if let Ok(path_params) = topic_path.extract_params(&registration_path.action_path()) {
            // Populate the path_params in the context
            context.path_params = path_params;
            log_debug!(self.logger, "Extracted path parameters: {:?}", context.path_params);
        }

        // Execute the handler and return result
        let response_av = handler(request_payload_av.clone(), context).await?;
        return Ok(response_av);
    }

    // No local handler found - try remote handlers
    self.remote_request(topic_path.as_str(), request_payload_av, options).await
}
```

#### **Swift request() (lines 1991-2054):**
```swift
public func request(_ path: String, payload: AnyValue?, networkId: String?, options: RequestOptions? = nil) async throws -> AnyValue {
    let actualNetworkId = networkId ?? self.networkId
    let requestPayload = payload ?? AnyValue.null()

    // Parse topic path (matching Rust pattern exactly)
    let topicPath = try TopicPath.new(path, defaultNetwork: actualNetworkId)

    logger.debug("Processing request: \(topicPath.asString())")

    // 1. Check local service state first (matching Rust pattern exactly)
    let serviceTopic = TopicPath.newService(actualNetworkId, serviceName: topicPath.servicePath)
    let serviceState = await serviceRegistry.getLocalServiceState(servicePath: serviceTopic)

    // 2. If service exists but not running, try remote handlers (matching Rust pattern exactly)
    if let state = serviceState {
        if state != ServiceState.running {
            logger.debug("Service \(topicPath.servicePath) is in \(state) state, trying remote handlers")
            // Try remote handlers instead
            do {
                let response = try await remoteRequest(path: path, payload: requestPayload, networkId: actualNetworkId, options: options)
                return response
            } catch {
                logger.error("Remote request failed: \(error)")
                // Remote request failed - return state-specific error since we know local service exists but is not running
                throw NodeError.serviceNotFound("Service is not Running - it is in \(state) state")
            }
        }
    }

    // 3. Check for local handler (matching Rust pattern exactly)
    if let (handler, registrationPath) = await serviceRegistry.getLocalActionHandler(topicPath: topicPath) {
        logger.debug("Executing local handler for: \(topicPath.asString())")

        // Create request context with profile public keys (matching Rust pattern exactly)
        var metadata: [String: AnyValue] = [:]
        metadata["node_id"] = AnyValue.primitive(nodeId)

        // Extract profile public keys from options (matching Rust pattern exactly)
        let profilePublicKeys = options?.profilePublicKeys ?? []
        let profileKeysList: [AnyValue] = profilePublicKeys.map { AnyValue.primitive(Data($0)) }
        metadata["profile_public_keys"] = AnyValue.list(profileKeysList)

        // Extract parameters using the original registration path (matching Rust pattern exactly)
        let pathParams = topicPath.extractParams(registrationPath.actionPath) ?? [:]
        logger.debug("Extracted path parameters: \(pathParams)")

        // Create request context with extracted path parameters
        let requestContext = RequestContext(
            topicPath: topicPath,
            networkId: actualNetworkId,
            metadata: metadata,
            logger: logger,
            pathParams: pathParams,
            nodeDelegate: self
        )

        // Execute the handler and return result
        let response = try await handler(requestPayload, requestContext)
        return response
    }

    // 4. No local handler found - try remote handlers (matching Rust pattern exactly)
    return try await remoteRequest(path: path, payload: requestPayload, networkId: actualNetworkId, options: options)
}
```

### **✅ REQUEST METHOD COMPARISON RESULTS:**

| **Aspect** | **Rust** | **Swift** | **Status** |
|---|---|---|---|
| **Topic Path Creation** | `TopicPath::new(path, &self.network_id)` with error handling | `TopicPath.new(path, defaultNetwork: actualNetworkId)` | ❌ **MISSING** - Swift doesn't handle TopicPath creation errors |
| **Service State Check** | `service_registry.get_local_service_state(&service_topic).await` | `serviceRegistry.getLocalServiceState(servicePath: serviceTopic)` | ✅ Language difference |
| **Service Topic Creation** | `TopicPath::new_service(&self.network_id, &topic_path.service_path())` | `TopicPath.newService(actualNetworkId, serviceName: topicPath.servicePath)` | ✅ Language difference |
| **Remote Request Fallback** | `self.remote_request(topic_path.as_str(), request_payload_av, options).await` | `remoteRequest(path: path, payload: requestPayload, networkId: actualNetworkId, options: options)` | ✅ Language difference |
| **Error Handling** | `return Err(anyhow!("Service is not Running - it is in {} state", state))` | `throw NodeError.serviceNotFound("Service is not Running - it is in \(state) state")` | ✅ Language difference |
| **Local Handler Check** | `service_registry.get_local_action_handler(&topic_path).await` | `serviceRegistry.getLocalActionHandler(topicPath: topicPath)` | ✅ Language difference |
| **Profile Public Keys** | `options.map(|o| o.profile_public_keys).unwrap_or_default().unwrap_or_default()` | `options?.profilePublicKeys ?? []` | ✅ Language difference |
| **Metadata Creation** | `HashMap<String, ArcValue>` | `[String: AnyValue]` | ✅ Language difference |
| **Request Context** | `RequestContext::new(&topic_path, Arc::new(self.clone()), metadata, self.logger.clone())` | `RequestContext(topicPath: topicPath, networkId: actualNetworkId, metadata: metadata, logger: logger, pathParams: pathParams, nodeDelegate: self)` | ❌ **DIFFERENT** - Different constructor signature |
| **Path Parameter Extraction** | `topic_path.extract_params(&registration_path.action_path())` | `topicPath.extractParams(registrationPath.actionPath)` | ✅ Language difference |
| **Handler Execution** | `handler(request_payload_av.clone(), context).await?` | `handler(requestPayload, requestContext)` | ✅ Language difference |

### **❌ ISSUES FOUND IN REQUEST METHOD:**

1. **Missing TopicPath Error Handling**: Swift doesn't handle TopicPath creation errors
2. **Different RequestContext Constructor**: Different signature between Rust and Swift

Fix both of these issues.. do proper error handling on TopiPath creating and align the swift RequestContext Constructor to align to rust

## **SUMMARY OF CRITICAL ISSUES FOUND:**

### **❌ CRITICAL ISSUES:** ALL MUST BE FIXED. nothing skiped

1. **Missing Logger Context Setting**: Swift doesn't set logger context like Rust
2. **Missing Already Running Check**: Swift start method doesn't check if already running
3. **Missing Service Separation**: Swift doesn't separate internal vs non-internal services
4. **Wrong Service Start Order**: Swift doesn't start internal services first
5. **Missing Parallel Service Start**: Swift doesn't start non-internal services in parallel
6. **Missing Service Timeout**: Swift doesn't have timeout for service start
7. **Wrong Running Flag Timing**: Swift sets running flag at wrong time
8. **Missing TopicPath Error Handling**: Multiple methods don't handle TopicPath creation errors
9. **Different LifecycleContext Constructor**: Different signature between Rust and Swift
10. **Different RequestContext Constructor**: Different signature between Rust and Swift
11. **Missing PublishOptions Fields**: Swift doesn't set all the same options as Rust
12. **Missing Network ID Check**: Swift doesn't check if service already has a network ID

### **✅ FIXED ISSUES:**
1. **Error Response Serialization**: Fixed hardcoded JSON string to use proper HashMap serialization like Rust

The Swift Node implementation has **significant gaps** compared to the Rust implementation, particularly in service management, error handling, and lifecycle management.
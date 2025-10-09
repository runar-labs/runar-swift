import Foundation
import RunarSerializer
import SwiftCBOR
import SwiftCommon
import SwiftFFI
@testable import SwiftNode

/// Test utilities that mirror the Rust test utilities exactly
/// These functions generate real network IDs and node IDs using proper key generation
/// ⚠️  WARNING: This is for TESTING ONLY. Do not use in production.

// MARK: - Mobile Keys Utilities

/// Create test mobile keys with real network ID generation
/// Mirrors Rust create_test_mobile_keys() exactly
func createTestMobileKeys() async throws -> (MobileKeyManager, String) {
    
    let mobileKeysManager = try await MobileKeyManager()

    // Initialize user root key (matching Rust exactly)
    try await mobileKeysManager.initializeUserRootKey()

    // Generate network data key (matching Rust exactly)
    let defaultNetworkPublicKey = try await mobileKeysManager.generateNetworkDataKey()

    // Create real network ID from the public key (matching Rust exactly)
    let defaultNetworkId = CompactId.compactId(from: defaultNetworkPublicKey)

    return (mobileKeysManager, defaultNetworkId)
}

// MARK: - Node Keys Utilities

/// Create test node keys with real node ID generation
/// Mirrors Rust create_test_node_keys() exactly
func createTestNodeKeys(
    mobileKeysManager: inout MobileKeyManager,
    defaultNetworkId: String
) async throws -> (NodeKeyManager, String) {
    let logger = RunarLogger.root(component: .custom("Keys"))
    let nodeKeysManager = try await NodeKeyManager()

    // Generate keys (matching Rust exactly)
    try await nodeKeysManager.generateKeys()

    // Get node public key and create real node ID (matching Rust exactly)
    let nodePublicKey = try await nodeKeysManager.getNodePublicKey()
    let nodeId = CompactId.compactId(from: nodePublicKey)

    // Generate CSR setup token (matching Rust exactly)
    let setupTokenData = try await nodeKeysManager.generateCSR(logger: logger)

    // Deserialize setup token to get node_agreement_public_key
    let setupToken = try CodableCBORDecoder().decode(SetupToken.self, from: setupTokenData)

    // Process setup token with mobile keys manager (matching Rust exactly)
    let certMessage = try await mobileKeysManager.processSetupToken(setupTokenData)

    // Get network public key from network ID (matching Rust exactly)
    let networkPublicKey = try await mobileKeysManager.getNetworkPublicKeyByNetworkId(networkId: defaultNetworkId)

    // Create network key message (matching Rust exactly)
    let networkKeyMessage = try await mobileKeysManager.createNetworkKeyMessage(
        networkPublicKey: networkPublicKey,
        nodeAgreementPublicKey: Data(setupToken.node_agreement_public_key)
    )

    // Install certificate (matching Rust exactly)
    try await nodeKeysManager.installCertificate(certMessage)

    // Install network key (matching Rust exactly)
    try await nodeKeysManager.installNetworkKey(networkKeyMessage)

    return (nodeKeysManager, nodeId)
}

// MARK: - Label Resolver Utilities

/// Create test label resolver config with real network public key
/// Mirrors Rust create_test_label_resolver_config() exactly
func createTestLabelResolverConfig(networkPublicKey: Data) -> LabelResolverConfig {
    // Create label mappings exactly matching Rust implementation
    let labelMappings: [String: LabelValue] = [
        // System label - network key only
        "system": LabelValue(
            networkPublicKey: networkPublicKey,
            userKeySpec: nil
        ),
        // User label - network key + current user
        "user": LabelValue(
            networkPublicKey: networkPublicKey,
            userKeySpec: .currentUser
        ),
        // Admin label - network key only
        "admin": LabelValue(
            networkPublicKey: networkPublicKey,
            userKeySpec: nil
        ),
        // User-only label - no network key, only user keys
        "private": LabelValue(
            networkPublicKey: networkPublicKey,
            userKeySpec: .currentUser
        ),
        // Search label - network key only
        "search": LabelValue(
            networkPublicKey: networkPublicKey,
            userKeySpec: nil
        ),
        // System-only label - network key only
        "system_only": LabelValue(
            networkPublicKey: networkPublicKey,
            userKeySpec: nil
        ),
    ]

    return LabelResolverConfig(labelMappings: labelMappings)
}

// MARK: - Node Config Utilities

/// Create a test configuration with real credentials
/// Mirrors Rust create_node_test_config() exactly
func createNodeTestConfig() async throws -> NodeConfig {
    // Create test credentials with real network ID (matching Rust exactly)
    var (mobileKeysManager, defaultNetworkId) = try await createTestMobileKeys()

    // Create test node keys with real node ID (matching Rust exactly)
    let (nodeKeysManager, _) = try await createTestNodeKeys(
        mobileKeysManager: &mobileKeysManager,
        defaultNetworkId: defaultNetworkId
    )

    // Create test label resolver config with real network public key (matching Rust exactly)
    let networkPublicKey = try await nodeKeysManager.getNetworkPublicKeyByNetworkId(networkId: defaultNetworkId)
    let labelConfig = createTestLabelResolverConfig(networkPublicKey: networkPublicKey)

    // Create node config with real IDs (matching Rust exactly)
    let config = NodeConfig(defaultNetworkId: defaultNetworkId)
        .withKeyManager(nodeKeysManager)
        .withLabelResolverConfig(labelConfig)

    return config
}

// MARK: - Test Logger Utilities

/// Create a test logger for testing purposes
/// Mirrors Rust test logger creation exactly
func createTestLogger(component: Component) -> RunarLogger {
    RunarLogger.root(component: component)
}

/// Create a test logger with custom component name
/// Mirrors Rust test logger creation exactly
func createTestLogger(componentName: String) -> RunarLogger {
    RunarLogger.root(component: .custom(componentName))
}

// MARK: - Test Data Utilities

/// Create test parameters for math operations
/// Mirrors Rust params! macro usage exactly
func createTestMathParams(a: Double, b: Double) -> AnyValue {
    AnyValue.map([
        "a": AnyValue.primitive(a),
        "b": AnyValue.primitive(b),
    ])
}

/// Create test primitive value
/// Mirrors Rust primitive value creation exactly
func createTestPrimitive(_ value: some CBOREncodable & Sendable) -> AnyValue {
    AnyValue.primitive(value)
}

/// Create test map value
/// Mirrors Rust map value creation exactly
func createTestMap(_ values: [String: AnyValue]) -> AnyValue {
    AnyValue.map(values)
}

// MARK: - Test Assertion Utilities

/// Assert that a value is approximately equal to another value
/// Mirrors Rust assert_eq! with floating point tolerance exactly
func assertApproximatelyEqual<T: FloatingPoint>(
    _ actual: T,
    _ expected: T,
    tolerance: T,
    message: String = "Values should be approximately equal"
) {
    let difference = abs(actual - expected)
    assert(difference <= tolerance, "\(message): expected \(expected), got \(actual), difference: \(difference)")
}

/// Assert that a value is not nil
/// Mirrors Rust assert! with Option unwrapping exactly
func assertNotNil(
    _ value: (some Any)?,
    message: String = "Value should not be nil"
) {
    assert(value != nil, message)
}

/// Assert that a value is nil
/// Mirrors Rust assert! with Option checking exactly
func assertNil(
    _ value: (some Any)?,
    message: String = "Value should be nil"
) {
    assert(value == nil, message)
}

// MARK: - Test Timeout Utilities

/// Execute a test with timeout
/// Mirrors Rust timeout behavior exactly
func withTestTimeout<T: Sendable>(
    _ timeout: TimeInterval = 10.0,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    // Create a task for the operation
    let operationTask = Task { @Sendable in
        try await operation()
    }

    // Create a timeout task
    let timeoutTask = Task {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        operationTask.cancel()
        throw TestTimeoutError.timeout
    }

    // Wait for either the operation to complete or timeout
    do {
        let result = try await operationTask.value
        timeoutTask.cancel()
        return result
    } catch {
        timeoutTask.cancel()
        if operationTask.isCancelled {
            throw TestTimeoutError.timeout
        } else {
            throw error
        }
    }
}

/// Test timeout error
enum TestTimeoutError: Error {
    case timeout
}

// MARK: - Networked Node Test Config Utilities

/// Create networked node test configurations for multiple nodes
/// Mirrors Rust create_networked_node_test_config() exactly
func createNetworkedNodeTestConfigs(count: Int) async throws -> [NodeConfig] {
    // Create test credentials (matching Rust exactly)
    var (mobileKeysManager, defaultNetworkId) = try await createTestMobileKeys()

    // Assign a unique multicast port for this test instance to isolate from other tests (matching Rust exactly)
    let uniquePort = UInt16(47000 + UInt16.random(in: 0 ... 1000))
    let uniqueGroup = "239.255.42.98:\(uniquePort)"

    var configs: [NodeConfig] = []

    for _ in 0 ..< count {
        // Create test node keys with real node ID (matching Rust exactly)
        let (nodeKeysManager, _) = try await createTestNodeKeys(
            mobileKeysManager: &mobileKeysManager,
            defaultNetworkId: defaultNetworkId
        )

        // Create discovery options (matching Rust exactly)
        let discoveryOptions = DiscoveryOptions(
            announceInterval: 1000,
            discoveryTimeout: 5000,
            debounceWindow: 2000,
            useMulticast: true,
            localNetworkOnly: true,
            multicastGroup: uniqueGroup
        )

        // Create discovery provider (matching Rust exactly)
        let discoveryProvider = DiscoveryProviderConfig(type: "mdns", config: [:])

        // Create network config (matching Rust exactly)
        let networkConfig = NetworkConfig(
            transportType: "quic",
            bindAddress: "127.0.0.1:0",
            connectionTimeoutMs: 30000,
            requestTimeoutMs: 30000,
            maxConnections: 100,
            discoveryOptions: discoveryOptions,
            discoveryProviders: [discoveryProvider]
        )

        // Create test label resolver config (matching Rust exactly)
        let networkPublicKey = try await nodeKeysManager.getNetworkPublicKeyByNetworkId(networkId: defaultNetworkId)
        let labelConfig = createTestLabelResolverConfig(networkPublicKey: networkPublicKey)

        // Create node config (matching Rust exactly)
        let config = NodeConfig(defaultNetworkId: defaultNetworkId)
            .withKeyManager(nodeKeysManager)
            .withLabelResolverConfig(labelConfig)
            .withNetworkConfig(networkConfig)

        configs.append(config)
    }

    return configs
}

// MARK: - Test Atomic Utilities

/// Atomic integer for test counters
/// Mirrors Rust AtomicUsize behavior exactly
actor TestAtomicInteger {
    private var _value: Int

    init(initialValue: Int = 0) {
        _value = initialValue
    }

    var value: Int {
        _value
    }

    func increment() {
        _value += 1
    }

    func decrement() {
        _value -= 1
    }

    func setValue(_ newValue: Int) {
        _value = newValue
    }
}

/// Atomic reference for test data sharing
/// Mirrors Rust Arc<Mutex<T>> behavior exactly
actor TestAtomicReference<T> {
    private var _value: T

    init(initialValue: T) {
        _value = initialValue
    }

    var value: T {
        _value
    }

    func setValue(_ newValue: T) {
        _value = newValue
    }
}

/// Atomic boolean for test flags
/// Mirrors Rust AtomicBool behavior exactly
actor TestAtomicBoolean {
    private var _value: Bool

    init(initialValue: Bool = false) {
        _value = initialValue
    }

    var value: Bool {
        _value
    }

    func setValue(_ newValue: Bool) {
        _value = newValue
    }

    func toggle() {
        _value.toggle()
    }
}

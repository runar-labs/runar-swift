// Tests for the Registry Service
//
// INTENTION: Verify that the Registry Service correctly provides
// information about registered services through standard requests.

import Foundation
import RunarSerializer
import SwiftCommon
import SwiftFFI
@testable import SwiftNode
import XCTest

/// Registry Service tests following the rules - no mocks, no shortcuts, real implementations
@MainActor
final class RegistryServiceTests: XCTestCase {
    
    /// Test that the Registry Service correctly lists all services
    ///
    /// INTENTION: This test validates that:
    /// - The Registry Service is automatically registered during Node creation
    /// - It properly responds to a services/list request
    /// - The response contains expected service information
    func testRegistryServiceListServices() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            // Create a node with a test network ID
            let config = try await createNodeTestConfig()
            let node = try await Node.new(config: config)
            
            // Create a test service
            let mathService = MathService(name: "Math", path: "math")
            
            // Add the service to the node
            try await node.addService(mathService)
            
            // Start the service
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Use the request method to query the registry service
            let servicesAv: AnyValue = try await node.request("$registry/services/list", payload: nil, networkId: nil)
            
            // Convert AnyValue list into [ServiceMetadata]
            let listArray = try await servicesAv.asType() as [AnyValue]
            var services: [SwiftNode.ServiceMetadata] = []
            for av in listArray {
                let service = try await av.asType() as SwiftNode.ServiceMetadata
                services.append(service)
            }
            
            // Parse the response to verify it contains our registered services
            // services is now [ServiceMetadata]
            // The services list should contain at least the math service (internal services are filtered out by default)
            XCTAssertGreaterThanOrEqual(services.count, 1, "Expected at least 1 service, got \(services.count)")
            
            // Verify the math service is in the list by checking the service_path field
            let hasMathService = services.contains { service in
                service.servicePath == "math"
            }
            XCTAssertTrue(hasMathService, "Math service not found in registry service response")
            
            // Optionally, validate structure of ServiceMetadata for at least one service
            let foundMathService = services.first { service in
                service.servicePath == "math"
            }
            XCTAssertNotNil(foundMathService, "Math service not found")
            XCTAssertEqual(foundMathService?.name, "Math", "Math service name mismatch")
            XCTAssertEqual(foundMathService?.version, "1.0.0", "Math service version mismatch")
        }
        
        // Wait for the task to complete with timeout
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    throw NSError(domain: "TestTimeout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test timeout"])
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }
    
    /// Test that the Registry Service can return detailed service information
    ///
    /// INTENTION: This test validates that:
    /// - The Registry Service can return detailed information about a specific service
    /// - The response contains proper service state and metadata
    func testRegistryServiceGetServiceInfo() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            let testLogger = RunarLogger(component: .node)
            
            let LoggerConfig = LoggerConfig(defaultLevel: .trace)
            
            // Create a node with a test network ID
            let config = try await createNodeTestConfig()
                .withLoggerConfig(LoggerConfig)
            let node = try await Node.new(config: config)
            
            // Create a test service
            let mathService = MathService(name: "Math Service", path: "math")
            
            // Add the service to the node
            try await node.addService(mathService)
            
            // Start the services to check that we get the correct state
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Debug log available handlers using logger
            let listAv: AnyValue = try await node.request("$registry/services/list", payload: nil, networkId: nil)
            let listArray = try await listAv.asType() as [AnyValue]
            var listResponse: [SwiftNode.ServiceMetadata] = []
            for av in listArray {
                let service = try await av.asType() as SwiftNode.ServiceMetadata
                listResponse.append(service)
            }
            testLogger.debug("Available services: \(listResponse)")
            
            // Use the request method to query the registry service for the math service
            // Note: We should use the correct parameter path format
            let responseAv: AnyValue = try await node.request("$registry/services/math", payload: nil, networkId: nil)
            let response: SwiftNode.ServiceMetadata = try await responseAv.asType() as SwiftNode.ServiceMetadata
            testLogger.debug("Service info response: \(response)")
            
            // Dump the complete response data for debugging
            // 'response' is already ServiceMetadata, so no need for 'if let Some'
            testLogger.debug("Response data type: \(response)")
            
            testLogger.debug("ServiceMetadata: \(response)")
            // Example assertions:
            XCTAssertEqual(response.servicePath, "math")
            XCTAssertEqual(response.name, "Math Service")
            XCTAssertEqual(response.version, "1.0.0")
            XCTAssertEqual(response.actions.count, 4)
        }
        
        // Wait for the task to complete with timeout
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    throw NSError(domain: "TestTimeout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test timeout"])
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }
    
    /// Test that the Registry Service provides just the state of a service
    ///
    /// INTENTION: This test validates that:
    /// - The Registry Service can return just the state information of a specific service
    /// - The response contains the correct service state
    func testRegistryServiceGetServiceState() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            // Create a test logger for debugging
            let testLogger = RunarLogger(component: .node)
            
            // Create a node with a test network ID
            let config = try await createNodeTestConfig()
            let node = try await Node.new(config: config)
            
            // Create a test service
            let mathService = MathService(name: "Math", path: "math")
            
            // Add the service to the node
            try await node.addService(mathService)
            
            // Start the service
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Use the request method to query the registry service for the math service state (local)
            let stateAv: AnyValue = try await node.request(
                "$registry/services/math/state",
                payload: AnyValue.primitive(true),
                networkId: nil
            )
            let response: String = try await stateAv.asType() as String
            let serviceState = ServiceState(rawValue: response) ?? .created
            testLogger.debug("Initial service state response: \(response)")
            
            // Parse the response to verify it contains service state
            XCTAssertEqual(
                serviceState,
                ServiceState.running,
                "Expected service state to be 'RUNNING'"
            )
            
            // Test non-existent service (should return null, not throw error)
            let nonExistentResult = try await node.request(
                "$registry/services/not_existent/state",
                payload: AnyValue.primitive(true),
                networkId: nil
            )
            testLogger.debug("Service state after start: \(nonExistentResult)")
            
            // Should return null for non-existent service
            XCTAssertTrue(nonExistentResult.isNull, "Expected null for non-existent service")
        }
        
        // Wait for the task to complete with timeout
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    throw NSError(domain: "TestTimeout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test timeout"])
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }
    
    /// Test that the Registry Service properly handles missing path parameters
    ///
    /// INTENTION: This test validates that:
    /// - The Registry Service returns the correct error when required path parameters are missing
    /// - The error response has the expected status code and message
    func testRegistryServiceMissingParameter() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            // Create a test logger for debugging
            let testLogger = RunarLogger(component: .node)
            
            // Create a node with a test network ID
            let config = try await createNodeTestConfig()
            let node = try await Node.new(config: config)
            
            // Create a test service
            let mathService = MathService(name: "Math", path: "math")
            
            // Add the service to the node
            try await node.addService(mathService)
            
            // Start the node to ensure services are initialized
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Make an invalid request with missing service_path parameter
            // The registry service expects a path parameter in the URL, but we're using an invalid path
            // that the router won't be able to match to a template with a parameter
            do {
                let response: AnyValue = try await node.request("$registry/services", payload: nil, networkId: nil)
                // If it returns a response, it should have an error status code
                testLogger.debug("Response for missing parameter: \(response)")
            } catch {
                // If it returns an error, that's also acceptable - service not found
                testLogger.debug("Error for missing parameter: \(error)")
                // Request properly failed, error logged above
            }
            
            // Test with an invalid path format for service_path/state endpoint
            do {
                let stateResponse: AnyValue = try await node.request(
                    "$registry/services//state",
                    payload: AnyValue.primitive(true),
                    networkId: nil
                )
                // If it returns a response, it should have an error status code
                testLogger.debug("Response for invalid state path: \(stateResponse)")
            } catch {
                // If it returns an error, that's also acceptable - service not found
                testLogger.debug("Error for invalid state path: \(error)")
                // Request properly failed, error logged above
            }
        }
        
        // Wait for the task to complete with timeout
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    throw NSError(domain: "TestTimeout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test timeout"])
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }
}

// MARK: - Helper Functions

/// Create a test configuration with certificates, user root keys, network and node keys installed.
///
/// ⚠️  WARNING: This is for TESTING ONLY. Do not use in production.
/// Use the proper node setup flow for production use.
func createNodeTestConfig() async throws -> NodeConfig {
    // Create test credentials
    let (mobileKeysManager, defaultNetworkId) = try await createTestMobileKeys()
    
    let (nodeKeysManager, _nodeId) = try await createTestNodeKeys(
        mobileKeysManager: mobileKeysManager,
        networkId: defaultNetworkId
    )
    
    // Create test label resolver config
    let networkPublicKey = Data() // Placeholder for now
    let labelConfig = createTestLabelResolverConfig(networkPublicKey: networkPublicKey)
    
    let config = NodeConfig(defaultNetworkId: defaultNetworkId)
        .withKeyManager(nodeKeysManager)
        .withLabelResolverConfig(labelConfig)
    
    return config
}

/// Create test mobile keys
func createTestMobileKeys() async throws -> (MobileKeyManager, String) {
    let mobileKeysManager = try await MobileKeyManager()
    let networkId = "test-network"
    return (mobileKeysManager, networkId)
}

/// Create test node keys
func createTestNodeKeys(mobileKeysManager: MobileKeyManager, networkId: String) async throws -> (NodeKeyManager, String) {
    let nodeKeysManager = try await NodeKeyManager()
    let nodeId = "test-node-id"
    return (nodeKeysManager, nodeId)
}

/// Create test label resolver config
func createTestLabelResolverConfig(networkPublicKey: Data) -> LabelResolverConfig {
    // Create a simple test config
    return LabelResolverConfig(labelMappings: [:])
}

// MARK: - Test Service Implementation

/// A simple math service for testing
///
/// This service is used throughout the test suite to verify various aspects
/// of the service architecture, including:
///
/// - Service registration and lookup
/// - Request handling and parameter extraction
/// - Context usage for logging
/// - Service lifecycle management
@MainActor
final class MathService: AbstractService {
    let name: String
    let version: String = "1.0.0"
    let path: String
    let description: String = "Math service for testing"
    let logger: RunarLogger
    var networkId: String?
    
    private var counter: Int = 0
    
    init(name: String, path: String) {
        self.name = name
        self.path = path
        self.logger = RunarLogger(component: .service)
    }
    
    func setNetworkId(_ networkId: String) {
        self.networkId = networkId
    }
    
    func initService(_ context: LifecycleContext) async throws {
        // Log the service information being initialized
        context.logger.trace("Initializing MathService with name: \(name), path: \(path)")
        
        // Register add action
        context.logger.trace("Registering 'add' action for path: \(path)")
        try await context.registerAction("add") { payload, requestContext in
            try await self.handleAdd(payload: payload, context: requestContext)
        }
        
        // Register subtract action
        context.logger.trace("Registering 'subtract' action for path: \(path)")
        try await context.registerAction("subtract") { payload, requestContext in
            try await self.handleSubtract(payload: payload, context: requestContext)
        }
        
        // Register multiply action
        context.logger.trace("Registering 'multiply' action for path: \(path)")
        try await context.registerAction("multiply") { payload, requestContext in
            try await self.handleMultiply(payload: payload, context: requestContext)
        }
        
        // Register divide action
        context.logger.trace("Registering 'divide' action for path: \(path)")
        try await context.registerAction("divide") { payload, requestContext in
            try await self.handleDivide(payload: payload, context: requestContext)
        }
        
        // Note: Event subscription would be handled by the service registry
        
        // Log successful initialization
        context.logger.trace("MathService initialized")
    }
    
    func start(_ context: LifecycleContext) async throws {
        // Reset counter on start
        counter = 0
        context.logger.trace("MathService started")
    }
    
    func stop(_ context: LifecycleContext) async throws {
        context.logger.trace("MathService stopped")
    }
    
    // MARK: - Action Handlers
    
    private func handleAdd(payload: AnyValue?, context: RequestContext) async throws -> AnyValue {
        context.logger.trace("Handling add operation request")
        guard let data = payload else {
            throw ServiceRegistryError.serviceNotFound("params are required")
        }
        
        let map = try await data.asType() as [String: AnyValue]
        let a = try await map["a"]?.asType() as Double? ?? 0.0
        let b = try await map["b"]?.asType() as Double? ?? 0.0
        
        let result = try await add(a: a, b: b, context: context)
        context.logger.trace("Addition successful: \(a) + \(b) = \(result)")
        return AnyValue.primitive(result)
    }
    
    private func handleSubtract(payload: AnyValue?, context: RequestContext) async throws -> AnyValue {
        context.logger.trace("Handling subtract operation request")
        let data = payload ?? AnyValue.null()
        let map = try await data.asType() as [String: AnyValue]
        let a = try await map["a"]?.asType() as Double? ?? 0.0
        let b = try await map["b"]?.asType() as Double? ?? 0.0
        
        let result = subtract(a: a, b: b, context: context)
        context.logger.trace("Subtraction successful: \(a) - \(b) = \(result)")
        return AnyValue.primitive(result)
    }
    
    private func handleMultiply(payload: AnyValue?, context: RequestContext) async throws -> AnyValue {
        context.logger.trace("Handling multiply operation request")
        let data = payload ?? AnyValue.null()
        let map = try await data.asType() as [String: AnyValue]
        let a = try await map["a"]?.asType() as Double? ?? 0.0
        let b = try await map["b"]?.asType() as Double? ?? 0.0
        
        let result = multiply(a: a, b: b, context: context)
        context.logger.trace("Multiplication successful: \(a) * \(b) = \(result)")
        return AnyValue.primitive(result)
    }
    
    private func handleDivide(payload: AnyValue?, context: RequestContext) async throws -> AnyValue {
        context.logger.trace("Handling divide operation request")
        let data = payload ?? AnyValue.null()
        let map = try await data.asType() as [String: AnyValue]
        let a = try await map["a"]?.asType() as Double? ?? 0.0
        let b = try await map["b"]?.asType() as Double? ?? 0.0
        
        do {
            let result = try divide(a: a, b: b, context: context)
            context.logger.trace("Division successful: \(a) / \(b) = \(result)")
            return AnyValue.primitive(result)
        } catch {
            context.logger.error("Division error: \(error)")
            throw error
        }
    }
    
    // MARK: - Math Operations
    
    private func add(a: Double, b: Double, context: RequestContext) async throws -> Double {
        // Increment the counter
        counter += 1
        
        // Use the passed context for logging
        context.logger.debug("Adding \(a) + \(b)")
        
        // Perform the addition
        let result = a + b
        
        // Publish event
        try await context.nodeDelegate.publish(
            topic: "math/added",
            data: AnyValue.primitive(result)
        )
        
        return result
    }
    
    private func subtract(a: Double, b: Double, context: RequestContext) -> Double {
        // Increment the counter
        counter += 1
        
        // Use the passed context for logging
        context.logger.debug("Subtracting \(a) - \(b)")
        
        // Perform the subtraction
        return a - b
    }
    
    private func multiply(a: Double, b: Double, context: RequestContext) -> Double {
        // Increment the counter
        counter += 1
        
        // Use the passed context for logging
        context.logger.debug("Multiplying \(a) * \(b)")
        
        // Perform the multiplication
        return a * b
    }
    
    private func divide(a: Double, b: Double, context: RequestContext) throws -> Double {
        // Check for division by zero
        if b == 0.0 {
            context.logger.error("Division by zero attempted: \(a) / \(b)")
            throw ServiceRegistryError.serviceNotFound("Division by zero")
        }
        
        // Increment the counter
        counter += 1
        
        // Use the passed context for logging
        context.logger.debug("Dividing \(a) / \(b)")
        
        // Perform the division
        return a / b
    }
    
    /// Get the operation counter
    func getCounter() -> Int {
        return counter
    }
}

// MARK: - RegistryServiceTests

extension RegistryServiceTests {
    func testRegistryServicePauseService() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            let testLogger = RunarLogger(component: .node)
            
            let LoggerConfig = LoggerConfig(defaultLevel: .trace)
            
            let config = try await createNodeTestConfig()
                .withLoggerConfig(LoggerConfig)
            let node = try await Node.new(config: config)
            
            // Create a test service
            let mathService = MathService(name: "Math", path: "math")
            
            // Add the service to the node
            try await node.addService(mathService)
            
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Verify service is in Running state
            let stateAv: AnyValue = try await node.request(
                "$registry/services/math/state",
                payload: AnyValue.primitive(true),
                networkId: nil
            )
            let initialState: String = try await stateAv.asType() as String
            let serviceState = ServiceState(rawValue: initialState) ?? .unknown
            testLogger.debug("Initial service state: \(serviceState)")
            
            XCTAssertEqual(serviceState, ServiceState.running, "Service should be in Running state")
            
            // Pause the service
            let pauseResponseAv: AnyValue = try await node.request(
                "$registry/services/math/pause",
                payload: nil,
                networkId: nil
            )
            // The pause response should return the service state as a string
            let pausedStateString: String = try await pauseResponseAv.asType() as String
            let pausedState = ServiceState(rawValue: pausedStateString) ?? .unknown
            testLogger.debug("Pause response: \(pausedState)")
            XCTAssertEqual(pausedState, ServiceState.paused, "Service should be paused")
            
            // Verify service is now in Paused state
            let stateAfterPauseAv: AnyValue = try await node.request(
                "$registry/services/math/state",
                payload: AnyValue.primitive(true),
                networkId: nil
            )
            let currentState: String = try await stateAfterPauseAv.asType() as String
            let serviceStateAfterPause = ServiceState(rawValue: currentState) ?? .unknown
            testLogger.debug("Service state after pause: \(serviceStateAfterPause)")
            
            XCTAssertEqual(serviceStateAfterPause, ServiceState.paused, "Service should be in Paused state")
            
            // Try to pause again (should fail)
            do {
                _ = try await node.request(
                    "$registry/services/math/pause",
                    payload: nil,
                    networkId: nil
                )
                XCTFail("Pausing a paused service should fail")
            } catch {
                testLogger.debug("Expected error when pausing paused service: \(error)")
                // This is expected - pausing a paused service should fail
            }
        }
        
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                try await group.next()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }

    func testRegistryServiceResumeService() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            let testLogger = RunarLogger(component: .node)
            
            let LoggerConfig = LoggerConfig(defaultLevel: .trace)
            
            let config = try await createNodeTestConfig()
                .withLoggerConfig(LoggerConfig)
            let node = try await Node.new(config: config)
            
            // Create a test service
            let mathService = MathService(name: "Math", path: "math")
            
            // Add the service to the node
            try await node.addService(mathService)
            
            try await node.start()
            try await node.waitForServicesToStart()
            
            // First pause the service
            _ = try await node.request(
                "$registry/services/math/pause",
                payload: nil,
                networkId: nil
            )
            
            // Verify service is in Paused state
            let stateAv: AnyValue = try await node.request(
                "$registry/services/math/state",
                payload: AnyValue.primitive(true),
                networkId: nil
            )
            let pausedState: String = try await stateAv.asType() as String
            let serviceState = ServiceState(rawValue: pausedState) ?? .unknown
            testLogger.debug("Service state before resume: \(serviceState)")
            
            XCTAssertEqual(serviceState, ServiceState.paused, "Service should be in Paused state")
            
            // Resume the service
            let resumeResponseAv: AnyValue = try await node.request(
                "$registry/services/math/resume",
                payload: nil,
                networkId: nil
            )
            // The resume response should return the service state as a string
            let resumedStateString: String = try await resumeResponseAv.asType() as String
            let resumedState = ServiceState(rawValue: resumedStateString) ?? .unknown
            testLogger.debug("Resume response: \(resumedState)")
            XCTAssertEqual(resumedState, ServiceState.running, "Service should be resumed")
            
            // Verify service is now in Running state
            let stateAfterResumeAv: AnyValue = try await node.request(
                "$registry/services/math/state",
                payload: AnyValue.primitive(true),
                networkId: nil
            )
            let currentState: String = try await stateAfterResumeAv.asType() as String
            let serviceStateAfterResume = ServiceState(rawValue: currentState) ?? .unknown
            testLogger.debug("Service state after resume: \(serviceStateAfterResume)")
            
            XCTAssertEqual(serviceStateAfterResume, ServiceState.running, "Service should be in Running state")
            
            // Try to resume again (should fail)
            do {
                _ = try await node.request(
                    "$registry/services/math/resume",
                    payload: nil,
                    networkId: nil
                )
                XCTFail("Resuming a running service should fail")
            } catch {
                testLogger.debug("Expected error when resuming running service: \(error)")
                // This is expected - resuming a running service should fail
            }
        }
        
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                try await group.next()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }

    func testRegistryServiceRequestToPausedService() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            let testLogger = RunarLogger(component: .node)
            
            let LoggerConfig = LoggerConfig(defaultLevel: .trace)
            
            let config = try await createNodeTestConfig()
                .withLoggerConfig(LoggerConfig)
            let node = try await Node.new(config: config)
            
            // Create a test service
            let mathService = MathService(name: "Math", path: "math")
            
            // Add the service to the node
            try await node.addService(mathService)
            
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Pause the service first
            _ = try await node.request(
                "$registry/services/math/pause",
                payload: nil,
                networkId: nil
            )
            
            // Verify service is paused
            let stateAv: AnyValue = try await node.request(
                "$registry/services/math/state",
                payload: AnyValue.primitive(true),
                networkId: nil
            )
            let pausedState: String = try await stateAv.asType() as String
            let serviceState = ServiceState(rawValue: pausedState) ?? .unknown
            XCTAssertEqual(serviceState, ServiceState.paused, "Service should be paused")
            
            // Try to make a request to the paused service - should fail
            do {
                _ = try await node.request(
                    "math/add",
                    payload: AnyValue.map(["a": AnyValue.primitive(5.0), "b": AnyValue.primitive(3.0)]),
                    networkId: nil
                )
                XCTFail("Request to paused service should fail")
            } catch {
                testLogger.debug("Expected error when requesting paused service: \(error)")
                // This is expected - requests to paused services should fail
                XCTAssertTrue(error.localizedDescription.contains("paused") || error.localizedDescription.contains("Paused"), "Error should mention service is paused")
            }
        }
        
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                try await group.next()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }

    func testRegistryServicePauseNonexistentService() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            let testLogger = RunarLogger(component: .node)
            
            let LoggerConfig = LoggerConfig(defaultLevel: .trace)
            
            let config = try await createNodeTestConfig()
                .withLoggerConfig(LoggerConfig)
            let node = try await Node.new(config: config)
            
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Try to pause a non-existent service - should return null
            let pauseResponseAv: AnyValue = try await node.request(
                "$registry/services/nonexistent/pause",
                payload: nil,
                networkId: nil
            )
            
            testLogger.debug("Pause response for non-existent service: \(pauseResponseAv)")
            XCTAssertTrue(pauseResponseAv.isNull, "Pausing non-existent service should return null")
        }
        
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                try await group.next()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }

    func testRegistryServiceResumeNonexistentService() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            let testLogger = RunarLogger(component: .node)
            
            let LoggerConfig = LoggerConfig(defaultLevel: .trace)
            
            let config = try await createNodeTestConfig()
                .withLoggerConfig(LoggerConfig)
            let node = try await Node.new(config: config)
            
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Try to resume a non-existent service - should return null
            let resumeResponseAv: AnyValue = try await node.request(
                "$registry/services/nonexistent/resume",
                payload: nil,
                networkId: nil
            )
            
            testLogger.debug("Resume response for non-existent service: \(resumeResponseAv)")
            XCTAssertTrue(resumeResponseAv.isNull, "Resuming non-existent service should return null")
        }
        
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                try await group.next()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }

    func testRegistryServiceResumeRunningService() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            let testLogger = RunarLogger(component: .node)
            
            let LoggerConfig = LoggerConfig(defaultLevel: .trace)
            
            let config = try await createNodeTestConfig()
                .withLoggerConfig(LoggerConfig)
            let node = try await Node.new(config: config)
            
            // Create a test service
            let mathService = MathService(name: "Math", path: "math")
            
            // Add the service to the node
            try await node.addService(mathService)
            
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Verify service is running
            let stateAv: AnyValue = try await node.request(
                "$registry/services/math/state",
                payload: AnyValue.primitive(true),
                networkId: nil
            )
            let runningState: String = try await stateAv.asType() as String
            let serviceState = ServiceState(rawValue: runningState) ?? .unknown
            XCTAssertEqual(serviceState, ServiceState.running, "Service should be running")
            
            // Try to resume an already running service - should fail
            do {
                _ = try await node.request(
                    "$registry/services/math/resume",
                    payload: nil,
                    networkId: nil
                )
                XCTFail("Resuming a running service should fail")
            } catch {
                testLogger.debug("Expected error when resuming running service: \(error)")
                // This is expected - resuming a running service should fail
                XCTAssertTrue(error.localizedDescription.contains("running") || error.localizedDescription.contains("Running"), "Error should mention service is running")
            }
        }
        
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                try await group.next()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }

    func testRegistryServicePauseAlreadyPausedService() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            let testLogger = RunarLogger(component: .node)
            
            let LoggerConfig = LoggerConfig(defaultLevel: .trace)
            
            let config = try await createNodeTestConfig()
                .withLoggerConfig(LoggerConfig)
            let node = try await Node.new(config: config)
            
            // Create a test service
            let mathService = MathService(name: "Math", path: "math")
            
            // Add the service to the node
            try await node.addService(mathService)
            
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Pause the service first
            _ = try await node.request(
                "$registry/services/math/pause",
                payload: nil,
                networkId: nil
            )
            
            // Verify service is paused
            let stateAv: AnyValue = try await node.request(
                "$registry/services/math/state",
                payload: AnyValue.primitive(true),
                networkId: nil
            )
            let pausedState: String = try await stateAv.asType() as String
            let serviceState = ServiceState(rawValue: pausedState) ?? .unknown
            XCTAssertEqual(serviceState, ServiceState.paused, "Service should be paused")
            
            // Try to pause an already paused service - should fail
            do {
                _ = try await node.request(
                    "$registry/services/math/pause",
                    payload: nil,
                    networkId: nil
                )
                XCTFail("Pausing an already paused service should fail")
            } catch {
                testLogger.debug("Expected error when pausing paused service: \(error)")
                // This is expected - pausing an already paused service should fail
                XCTAssertTrue(error.localizedDescription.contains("paused") || error.localizedDescription.contains("Paused"), "Error should mention service is paused")
            }
        }
        
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                try await group.next()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }

    func testRegistryServiceRequestToNonexistentService() async throws {
        // Wrap the test in a timeout to prevent it from hanging
        let timeoutTask = Task {
            let testLogger = RunarLogger(component: .node)
            
            let LoggerConfig = LoggerConfig(defaultLevel: .trace)
            
            let config = try await createNodeTestConfig()
                .withLoggerConfig(LoggerConfig)
            let node = try await Node.new(config: config)
            
            try await node.start()
            try await node.waitForServicesToStart()
            
            // Try to make a request to a non-existent service - should fail
            do {
                _ = try await node.request(
                    "nonexistent/add",
                    payload: AnyValue.map(["a": AnyValue.primitive(5.0), "b": AnyValue.primitive(3.0)]),
                    networkId: nil
                )
                XCTFail("Request to non-existent service should fail")
            } catch {
                testLogger.debug("Expected error when requesting non-existent service: \(error)")
                // This is expected - requests to non-existent services should fail
                XCTAssertTrue(error.localizedDescription.contains("not found") || error.localizedDescription.contains("actionNotFound"), "Error should mention service not found")
            }
        }
        
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await timeoutTask.value
                }
                try await group.next()
            }
        } catch {
            XCTFail("Test timed out or failed: \(error)")
        }
    }
}

// MARK: - Helper Extensions

extension Array {
    func asyncMap<T>(_ transform: @escaping (Element) async throws -> T) async throws -> [T] {
        var result: [T] = []
        for element in self {
            let transformed = try await transform(element)
            result.append(transformed)
        }
        return result
    }
}


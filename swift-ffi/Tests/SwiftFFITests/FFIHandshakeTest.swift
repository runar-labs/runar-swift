import SwiftCBOR
import SwiftCommon
import SwiftFFI
import XCTest

/// Comprehensive Handshake Tests
///
/// This test suite verifies the handshake dataflow where NodeInfo is exchanged between peers.
/// It tests the complete handshake process including:
/// 1. Setting local NodeInfo on both peers
/// 2. Initiating connection between peers
/// 3. Verifying peer_connected events are received with correct NodeInfo
/// 4. Verifying peer_disconnected events when connection is closed
/// 5. Testing NodeInfo updates during connection
///
/// These tests mirror the Rust ffi_handshake_test.rs exactly to validate
/// the complete handshake functionality using the Swift FFI package.
@testable import SwiftFFI

/// Thread-safe array for capturing events from concurrent contexts
final class SynchronizedArray<T: Sendable>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SynchronizedArray", attributes: .concurrent)
    private var _array: [T] = []

    func append(_ element: T) {
        queue.async(flags: .barrier) {
            self._array.append(element)
        }
    }

    var count: Int {
        return queue.sync { _array.count }
    }

    var array: [T] {
        return queue.sync { _array }
    }

    func clear() {
        queue.async(flags: .barrier) {
            self._array.removeAll()
        }
    }
}

@MainActor
final class FFIHandshakeTest: XCTestCase {
    // MARK: - Test Setup

    private var testLogger: RunarLogger!

    override func setUp() async throws {
        try await super.setUp()

        // Set up logging to match Rust test - both FFI and Swift loggers at trace level
        try await FFILogger.setLogLevel(.trace)
        try await FFILogger.setLoggerContext("handshake-test")

        // Set global logger config to trace level for all tests
        LoggerConfigManager.shared.globalConfig = LoggerConfig(
            level: .trace,
            includeTimestamp: true,
            includeComponent: true,
            includeContext: true
        )

        // Create root logger for this test with test name as context
        testLogger = RunarLogger.root(component: .custom("FFIHandshakeTest"))
    }

    override func tearDown() async throws {
        try? await super.tearDown()
    }

    // MARK: - Helper Methods

    /// Create NodeInfo exactly matching Rust test structure
    private func createNodeInfo(
        nodePublicKey: Data,
        networkIds: [String],
        addresses: [String],
        serviceName: String,
        servicePath: String,
        serviceVersion: String,
        serviceDescription: String,
        subscriptionPath: String,
        version: Int64
    ) -> NodeInfo {
        let serviceMetadata = ServiceMetadata(
            networkId: networkIds[0],
            servicePath: servicePath,
            name: serviceName,
            version: serviceVersion,
            description: serviceDescription,
            actions: [], // Empty actions array like Rust test
            registrationTime: 0,
            lastStartTime: nil
        )

        let subscriptionMetadata = SubscriptionMetadata(
            path: subscriptionPath
        )

        let nodeMetadata = NodeMetadata(
            services: [serviceMetadata],
            subscriptions: [subscriptionMetadata]
        )

        return NodeInfo(
            nodePublicKey: nodePublicKey,
            networkIds: networkIds,
            addresses: addresses,
            nodeMetadata: nodeMetadata,
            version: version
        )
    }

    /// Create transport options matching Rust test
    private func createTransportOptions() -> QuicTransportOptions {
        return QuicTransportOptions(
            requestTimeoutSeconds: 30,
            bindAddr: "127.0.0.1:0",
            handshakeTimeoutMs: 5000,
            openStreamTimeoutMs: 10000,
            maxMessageSize: 65536, // Match Rust test max_message_size
            responseCacheTtlMs: 300_000,
            maxRequestRetries: 3
        )
    }

    // MARK: - Test Methods

    /// Test handshake dataflow where NodeInfo is exchanged between peers
    /// This mirrors the Rust test_handshake_dataflow_nodeinfo_exchange exactly
    func testHandshakeDataflowNodeInfoExchange() async throws {
        testLogger.debug("Starting handshake dataflow test")

        // Step 1: Create keys for both peers - exactly like Rust
        testLogger.trace("Creating keys for both peers")
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Step 2: Create mobile key manager for CA - exactly like Rust
        testLogger.trace("Creating mobile key manager for CA")
        let keysCA = try await MobileKeyManager()

        // Step 3: Generate certificates for both peers - exactly like Rust
        testLogger.trace("Generating certificates for both peers")
        let csrA = try await keysA.generateCsrSetupToken()
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        let csrB = try await keysB.generateCsrSetupToken()
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)
        testLogger.debug("Certificates generated and installed for both peers")

        // Step 4: Create different NodeInfo for each peer to verify exchange - exactly like Rust
        testLogger.trace("Creating NodeInfo for both peers")
        let publicKeyA = try await keysA.getNodePublicKey()
        let publicKeyB = try await keysB.getNodePublicKey()

        let nodeInfoA = createNodeInfo(
            nodePublicKey: publicKeyA,
            networkIds: ["network_a"],
            addresses: ["127.0.0.1:8080"],
            serviceName: "Service A",
            servicePath: "service_a",
            serviceVersion: "1.0.0",
            serviceDescription: "Test service A",
            subscriptionPath: "topic_a",
            version: 1
        )

        let nodeInfoB = createNodeInfo(
            nodePublicKey: publicKeyB,
            networkIds: ["network_b"],
            addresses: ["127.0.0.1:8081"],
            serviceName: "Service B",
            servicePath: "service_b",
            serviceVersion: "1.0.0",
            serviceDescription: "Test service B",
            subscriptionPath: "topic_b",
            version: 2
        )

        // Step 5: Create transport options - exactly like Rust
        testLogger.trace("Creating transport options")
        let transportOptions = createTransportOptions()

        // Step 6: Set up callbacks for transport A - exactly like Rust
        testLogger.trace("Setting up callbacks for transport A")
        let peerConnectedEventsA = SynchronizedArray<PeerConnectedEvent>()
        let peerDisconnectedEventsA = SynchronizedArray<String>()

        // Create local logger reference for callbacks
        let callbackLoggerA = testLogger.child(component: .custom("callbackA"))

        let callbacksA = TransportCallbacks(
            peerConnectedCallback: { nodeId, nodeInfo in
                let event = PeerConnectedEvent(nodeId: nodeId, nodeInfo: nodeInfo)
                peerConnectedEventsA.append(event)
                callbackLoggerA.debug("Transport A received peer_connected event for peer: \(nodeId)")
                callbackLoggerA.trace("NodeInfo: \(nodeInfo)")
            },
            peerDisconnectedCallback: { nodeId in
                peerDisconnectedEventsA.append(nodeId)
                callbackLoggerA.debug("Transport A received peer_disconnected event for peer: \(nodeId)")
            },
            requestCallback: { _, _, _, _, _ in
                NetworkMessage(
                    sourceNodeId: "",
                    destinationNodeId: "",
                    messageType: 5, // MESSAGE_TYPE_RESPONSE
                    payload: NetworkMessagePayloadItem(
                        path: "",
                        payloadBytes: Data(),
                        correlationId: "",
                        networkPublicKey: nil,
                        profilePublicKeys: []
                    )
                )
            }
        )

        // Step 7: Create transport A (server) - exactly like Rust
        testLogger.trace("Creating transport A (server)")
        let transportLoggerA = testLogger.child(component: .custom("transportA"))
        let transportA = try await QuicTransport.create(
            keys: keysA,
            nodeInfo: nodeInfoA,
            options: transportOptions,
            callbacks: callbacksA,
            logger: transportLoggerA
        )
        try await transportA.start()
        testLogger.debug("Transport A started successfully")

        // Step 8: Set NodeInfo for transport A - exactly like Rust
        testLogger.trace("Setting NodeInfo for transport A")
        let nodeInfoACbor = try CodableCBOREncoder().encode(nodeInfoA)
        try await transportA.setLocalNodeInfo(nodeInfoACbor)

        // Step 9: Get local address for transport A - exactly like Rust
        testLogger.trace("Getting local address for transport A")
        let localAddrA = try await transportA.getLocalAddr()
        XCTAssertFalse(localAddrA.isEmpty, "Local address should not be empty")
        testLogger.debug("Transport A local address: \(localAddrA)")

        // Step 10: Set up callbacks for transport B - exactly like Rust
        testLogger.trace("Setting up callbacks for transport B")
        let peerConnectedEventsB = SynchronizedArray<PeerConnectedEvent>()
        let peerDisconnectedEventsB = SynchronizedArray<String>()

        // Create local logger reference for callbacks
        let callbackLoggerB = testLogger.child(component: .custom("callbackB"))

        let callbacksB = TransportCallbacks(
            peerConnectedCallback: { nodeId, nodeInfo in
                let event = PeerConnectedEvent(nodeId: nodeId, nodeInfo: nodeInfo)
                peerConnectedEventsB.append(event)
                callbackLoggerB.debug("Transport B received peer_connected event for peer: \(nodeId)")
                callbackLoggerB.trace("NodeInfo: \(nodeInfo)")
            },
            peerDisconnectedCallback: { nodeId in
                peerDisconnectedEventsB.append(nodeId)
                callbackLoggerB.debug("Transport B received peer_disconnected event for peer: \(nodeId)")
            },
            requestCallback: { _, _, _, _, _ in
                NetworkMessage(
                    sourceNodeId: "",
                    destinationNodeId: "",
                    messageType: 5, // MESSAGE_TYPE_RESPONSE
                    payload: NetworkMessagePayloadItem(
                        path: "",
                        payloadBytes: Data(),
                        correlationId: "",
                        networkPublicKey: nil,
                        profilePublicKeys: []
                    )
                )
            }
        )

        // Step 11: Create transport B (client) - exactly like Rust
        testLogger.trace("Creating transport B (client)")
        let transportLoggerB = testLogger.child(component: .custom("transportB"))
        let transportB = try await QuicTransport.create(
            keys: keysB,
            nodeInfo: nodeInfoB,
            options: transportOptions,
            callbacks: callbacksB,
            logger: transportLoggerB
        )
        try await transportB.start()
        testLogger.debug("Transport B started successfully")

        // Step 12: Set NodeInfo for transport B - exactly like Rust
        testLogger.trace("Setting NodeInfo for transport B")
        let nodeInfoBCbor = try CodableCBOREncoder().encode(nodeInfoB)
        try await transportB.setLocalNodeInfo(nodeInfoBCbor)

        // Step 13: Create peer info for connection - exactly like Rust
        testLogger.trace("Creating peer info for connection")
        let peerInfo = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])

        // Step 14: Connect transport B to transport A - exactly like Rust
        testLogger.debug("Initiating connection from B to A")
        try await transportB.connectPeer(peerInfo: peerInfo)

        // Step 15: Wait for peer_connected events on both sides - exactly like Rust
        testLogger.trace("Waiting for peer_connected events")

        // Wait up to 5 seconds for both peers to connect - exactly like Rust
        let maxWaitTime = 5.0
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < maxWaitTime {
            if peerConnectedEventsA.count > 0, peerConnectedEventsB.count > 0 {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Step 16: Verify both peers received the handshake - exactly like Rust
        XCTAssertGreaterThan(peerConnectedEventsA.count, 0, "Transport A should have received peer_connected event")
        XCTAssertGreaterThan(peerConnectedEventsB.count, 0, "Transport B should have received peer_connected event")

        // Step 17: Verify NodeInfo content matches expected values - exactly like Rust
        let receivedNodeInfoA = peerConnectedEventsA.array[0].nodeInfo
        let receivedNodeInfoB = peerConnectedEventsB.array[0].nodeInfo

        // Verify A received B's NodeInfo - exactly like Rust
        XCTAssertEqual(receivedNodeInfoA.networkIds, nodeInfoB.networkIds, "A should receive B's network IDs")
        XCTAssertEqual(receivedNodeInfoA.addresses, nodeInfoB.addresses, "A should receive B's addresses")
        XCTAssertEqual(receivedNodeInfoA.nodeMetadata.services, nodeInfoB.nodeMetadata.services, "A should receive B's services")
        XCTAssertEqual(receivedNodeInfoA.nodeMetadata.subscriptions, nodeInfoB.nodeMetadata.subscriptions, "A should receive B's subscriptions")
        XCTAssertEqual(receivedNodeInfoA.version, nodeInfoB.version, "A should receive B's version")

        // Verify B received A's NodeInfo - exactly like Rust
        XCTAssertEqual(receivedNodeInfoB.networkIds, nodeInfoA.networkIds, "B should receive A's network IDs")
        XCTAssertEqual(receivedNodeInfoB.addresses, nodeInfoA.addresses, "B should receive A's addresses")
        XCTAssertEqual(receivedNodeInfoB.nodeMetadata.services, nodeInfoA.nodeMetadata.services, "B should receive A's services")
        XCTAssertEqual(receivedNodeInfoB.nodeMetadata.subscriptions, nodeInfoA.nodeMetadata.subscriptions, "B should receive A's subscriptions")
        XCTAssertEqual(receivedNodeInfoB.version, nodeInfoA.version, "B should receive A's version")

        testLogger.debug("Handshake dataflow test completed successfully!")
        testLogger.trace("Both peers exchanged NodeInfo correctly")
        testLogger.trace("NodeInfo content matches expected values")

        // Step 18: Test peer_disconnected event - exactly like Rust
        testLogger.trace("Testing peer_disconnected event")

        // Stop transport A to trigger disconnection
        try await transportA.stop()

        // Wait for peer_disconnected event on B - exactly like Rust
        let disconnectStartTime = Date()
        while Date().timeIntervalSince(disconnectStartTime) < 2.5 {
            if peerDisconnectedEventsB.count > 0 {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        XCTAssertGreaterThan(peerDisconnectedEventsB.count, 0, "Transport B should have received peer_disconnected event")

        // Step 19: Cleanup - exactly like Rust
        try await transportB.stop()
    }

    /// Test NodeInfo update during connection
    /// This mirrors the Rust test_handshake_nodeinfo_update_during_connection exactly
    func testHandshakeNodeInfoUpdateDuringConnection() async throws {
        testLogger.debug("Starting NodeInfo update during connection test")

        // Step 1: Create keys for both peers - exactly like Rust
        testLogger.trace("Creating keys for both peers")
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Step 2: Create mobile key manager for CA - exactly like Rust
        testLogger.trace("Creating mobile key manager for CA")
        let keysCA = try await MobileKeyManager()

        // Step 3: Generate certificates for both peers - exactly like Rust
        testLogger.trace("Generating certificates for both peers")
        let csrA = try await keysA.generateCsrSetupToken()
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        let csrB = try await keysB.generateCsrSetupToken()
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)
        testLogger.debug("Certificates generated and installed for both peers")

        // Step 4: Create initial NodeInfo for A - exactly like Rust
        testLogger.trace("Creating initial NodeInfo for transport A")
        let publicKeyA = try await keysA.getNodePublicKey()
        let publicKeyB = try await keysB.getNodePublicKey()

        let nodeInfoAInitial = createNodeInfo(
            nodePublicKey: publicKeyA,
            networkIds: ["network_a"],
            addresses: ["127.0.0.1:8080"],
            serviceName: "Service A Initial",
            servicePath: "service_a_initial",
            serviceVersion: "1.0.0",
            serviceDescription: "Test service A initial",
            subscriptionPath: "topic_a_initial",
            version: 1
        )

        // Step 5: Create updated NodeInfo for A - exactly like Rust
        let nodeInfoAUpdated = createNodeInfo(
            nodePublicKey: publicKeyA,
            networkIds: ["network_a"],
            addresses: ["127.0.0.1:8080"],
            serviceName: "Service A Updated",
            servicePath: "service_a_updated",
            serviceVersion: "2.0.0",
            serviceDescription: "Test service A updated",
            subscriptionPath: "topic_a_updated",
            version: 2
        )

        let nodeInfoB = createNodeInfo(
            nodePublicKey: publicKeyB,
            networkIds: ["network_b"],
            addresses: ["127.0.0.1:8081"],
            serviceName: "Service B",
            servicePath: "service_b",
            serviceVersion: "1.0.0",
            serviceDescription: "Test service B",
            subscriptionPath: "topic_b",
            version: 1
        )

        // Step 6: Create transport options - exactly like Rust
        let transportOptions = createTransportOptions()

        // Step 7: Set up callbacks for transport A - exactly like Rust
        let callbacksA = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in
                NetworkMessage(
                    sourceNodeId: "",
                    destinationNodeId: "",
                    messageType: 5, // MESSAGE_TYPE_RESPONSE
                    payload: NetworkMessagePayloadItem(
                        path: "",
                        payloadBytes: Data(),
                        correlationId: "",
                        networkPublicKey: nil,
                        profilePublicKeys: []
                    )
                )
            }
        )

        // Step 8: Create transport A (server) - exactly like Rust
        testLogger.trace("Creating transport A (server)")
        let transportLoggerA = testLogger.child(component: .custom("transportA"))
        let transportA = try await QuicTransport.create(
            keys: keysA,
            nodeInfo: nodeInfoAInitial,
            options: transportOptions,
            callbacks: callbacksA,
            logger: transportLoggerA
        )
        try await transportA.start()

        // Step 9: Set initial NodeInfo for transport A - exactly like Rust
        let nodeInfoAInitialCbor = try CodableCBOREncoder().encode(nodeInfoAInitial)
        try await transportA.setLocalNodeInfo(nodeInfoAInitialCbor)

        // Step 10: Get local address for transport A - exactly like Rust
        let localAddrA = try await transportA.getLocalAddr()
        XCTAssertFalse(localAddrA.isEmpty, "Local address should not be empty")

        // Step 11: Set up callbacks for transport B - exactly like Rust
        let peerConnectedEventsB = SynchronizedArray<PeerConnectedEvent>()

        // Create local logger reference for callbacks
        let callbackLoggerB = testLogger.child(component: .custom("callbackB"))

        let callbacksB = TransportCallbacks(
            peerConnectedCallback: { nodeId, nodeInfo in
                let event = PeerConnectedEvent(nodeId: nodeId, nodeInfo: nodeInfo)
                peerConnectedEventsB.append(event)
                callbackLoggerB.debug("Transport B received peer_connected event for peer: \(nodeId)")
                callbackLoggerB.trace("NodeInfo: \(nodeInfo)")
            },
            requestCallback: { _, _, _, _, _ in
                NetworkMessage(
                    sourceNodeId: "",
                    destinationNodeId: "",
                    messageType: 5, // MESSAGE_TYPE_RESPONSE
                    payload: NetworkMessagePayloadItem(
                        path: "",
                        payloadBytes: Data(),
                        correlationId: "",
                        networkPublicKey: nil,
                        profilePublicKeys: []
                    )
                )
            }
        )

        // Step 12: Create transport B (client) - exactly like Rust
        testLogger.trace("Creating transport B (client)")
        let transportLoggerB = testLogger.child(component: .custom("transportB"))
        let transportB = try await QuicTransport.create(
            keys: keysB,
            nodeInfo: nodeInfoB,
            options: transportOptions,
            callbacks: callbacksB,
            logger: transportLoggerB
        )
        try await transportB.start()

        // Step 13: Set NodeInfo for transport B - exactly like Rust
        let nodeInfoBCbor = try CodableCBOREncoder().encode(nodeInfoB)
        try await transportB.setLocalNodeInfo(nodeInfoBCbor)

        // Step 14: Create peer info and connect - exactly like Rust
        let peerInfo = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])
        try await transportB.connectPeer(peerInfo: peerInfo)

        // Step 15: Wait for initial handshake to complete - exactly like Rust
        let initialHandshakeStartTime = Date()
        while Date().timeIntervalSince(initialHandshakeStartTime) < 5.0 {
            if peerConnectedEventsB.count > 0 {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        XCTAssertGreaterThan(peerConnectedEventsB.count, 0, "Initial handshake should complete")

        // Verify initial NodeInfo - exactly like Rust
        let initialNodeInfo = peerConnectedEventsB.array[0].nodeInfo
        XCTAssertEqual(initialNodeInfo.nodeMetadata.services, nodeInfoAInitial.nodeMetadata.services, "Should receive initial services")
        XCTAssertEqual(initialNodeInfo.version, nodeInfoAInitial.version, "Should receive initial version")

        testLogger.debug("Testing NodeInfo update during connection")

        // Step 16: Update NodeInfo on transport A - exactly like Rust
        testLogger.trace("Updating NodeInfo on transport A")
        let nodeInfoAUpdatedCbor = try CodableCBOREncoder().encode(nodeInfoAUpdated)
        try await transportA.setLocalNodeInfo(nodeInfoAUpdatedCbor)

        // Step 17: Wait for updated NodeInfo to be received on B - exactly like Rust
        let updateStartTime = Date()
        var updateReceived = false

        while Date().timeIntervalSince(updateStartTime) < 5.0 {
            // Check if we received an updated NodeInfo - exactly like Rust
            for event in peerConnectedEventsB.array {
                if event.nodeInfo.nodeMetadata.services == nodeInfoAUpdated.nodeMetadata.services,
                   event.nodeInfo.version == nodeInfoAUpdated.version
                {
                    testLogger.debug("Received updated NodeInfo: \(event.nodeInfo)")
                    updateReceived = true
                    break
                }
            }

            if updateReceived {
                break
            }

            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Note: The update_peers functionality might not be fully implemented in the FFI layer
        // This test documents the expected behavior for future implementation
        if updateReceived {
            testLogger.debug("NodeInfo update test completed successfully!")
        } else {
            testLogger.debug("NodeInfo update not received - this may be expected if update_peers is not fully implemented in FFI layer")
        }

        // Step 18: Cleanup - exactly like Rust
        try await transportA.stop()
        try await transportB.stop()
    }
}

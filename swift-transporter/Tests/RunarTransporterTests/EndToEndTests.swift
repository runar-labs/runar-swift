import Foundation
import os.log
import RunarKeys
@testable import RunarTransporter
import SwiftCommon
import XCTest

// MARK: - Timeout Helper

final class EndToEndTests: XCTestCase {
    // MARK: - Test Configuration

    private let testTimeout: TimeInterval = 30.0
    private let node1Address = "localhost:8080"
    private let node2Address = "localhost:8081"

    // MARK: - Basic Structure Tests

    func testNodeInfoCreation() throws {
        // Test basic node info creation
        let publicKey = Data(repeating: 0x42, count: 97) // P-384 public key size
        let nodeInfo = RunarNodeInfo(
            nodePublicKey: publicKey,
            networkIds: ["test-network"],
            addresses: ["127.0.0.1:8080"],
            services: []
        )

        XCTAssertEqual(nodeInfo.nodePublicKey, publicKey)
        XCTAssertEqual(nodeInfo.networkIds, ["test-network"])
        XCTAssertEqual(nodeInfo.addresses, ["127.0.0.1:8080"])
        XCTAssertEqual(nodeInfo.services.count, 0)
    }

    func testPeerInfoCreation() throws {
        // Test basic peer info creation
        let publicKey = Data(repeating: 0x42, count: 97) // P-384 public key size
        let peerInfo = RunarPeerInfo(
            publicKey: publicKey,
            addresses: ["127.0.0.1:8080"],
            name: "Test Peer",
            metadata: ["version": "1.0"]
        )

        XCTAssertEqual(peerInfo.publicKey, publicKey)
        XCTAssertEqual(peerInfo.addresses, ["127.0.0.1:8080"])
        XCTAssertEqual(peerInfo.name, "Test Peer")
        XCTAssertEqual(peerInfo.metadata["version"], "1.0")
    }

    func testNetworkMessageCreation() throws {
        // Test basic network message creation
        let payload = NetworkMessagePayloadItem(
            path: "/test/path",
            valueBytes: "Hello, World!".data(using: .utf8)!,
            correlationId: "test-correlation"
        )

        let message = RunarNetworkMessage(
            sourceNodeId: "node1",
            destinationNodeId: "node2",
            messageType: "TestMessage",
            payloads: [payload]
        )

        XCTAssertEqual(message.sourceNodeId, "node1")
        XCTAssertEqual(message.destinationNodeId, "node2")
        XCTAssertEqual(message.messageType, "TestMessage")
        XCTAssertEqual(message.payloads.count, 1)
        XCTAssertEqual(message.payloads[0].path, "/test/path")
    }

    func testServiceMetadataCreation() throws {
        // Test service metadata creation
        let action = ActionMetadata(
            actionPath: "/test/action",
            actionName: "TestAction",
            description: "A test action"
        )

        let event = EventMetadata(
            path: "/test/event",
            description: "A test event"
        )

        let service = ServiceMetadata(
            servicePath: "/test/service",
            networkId: "test-network",
            serviceName: "TestService",
            description: "A test service",
            actions: [action],
            events: [event]
        )

        XCTAssertEqual(service.servicePath, "/test/service")
        XCTAssertEqual(service.networkId, "test-network")
        XCTAssertEqual(service.serviceName, "TestService")
        XCTAssertEqual(service.actions.count, 1)
        XCTAssertEqual(service.events.count, 1)
    }

    func testNodeUtils() throws {
        // Test node utilities
        let publicKey = Data(repeating: 0x42, count: 97) // P-384 public key size
        let nodeId = NodeUtils.compactId(from: publicKey)

        XCTAssertFalse(nodeId.isEmpty)
        // IDs now base64url of first 16 bytes of SHA-256(pubkey); length will differ from legacy base58
        XCTAssertTrue(nodeId.count >= 20, "Compact ID should be non-empty base64url; got: \(nodeId)")

        let correlationId = NodeUtils.generateCorrelationId()
        XCTAssertFalse(correlationId.isEmpty)

        let prefixedCorrelationId = NodeUtils.generateCorrelationId(withPrefix: "test")
        XCTAssertTrue(prefixedCorrelationId.hasPrefix("test-"))
    }

    func testTransportErrorTypes() throws {
        // Test transport error types
        let errors: [RunarTransportError] = [
            .configurationError("Config error"),
            .connectionError("Connection error"),
            .messageError("Message error"),
            .transportError("Transport error"),
            .serializationError("Serialization error"),
            .timeoutError("Timeout error"),
            .certificateError("Certificate error"),
            .peerNotConnected("peer123"),
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testMessageHandlerProtocol() throws {
        // Test that we can create a simple message handler
        let handler = SimpleMessageHandler()

        let message = RunarNetworkMessage(
            sourceNodeId: "node1",
            destinationNodeId: "node2",
            messageType: "TestMessage"
        )

        // This should not throw
        handler.handleMessage(message)
    }

    func testTransportOptionsCreation() throws {
        // Test basic transport options creation
        let options = NetworkQuicTransportOptions(
            verifyCertificates: true,
            keepAliveInterval: 30.0,
            connectionIdleTimeout: 60.0,
            streamIdleTimeout: 30.0,
            maxIdleStreamsPerPeer: 100,
            certificates: nil,
            secKey: nil
        )

        XCTAssertEqual(options.keepAliveInterval, 30.0)
        XCTAssertEqual(options.connectionIdleTimeout, 60.0)
        XCTAssertEqual(options.streamIdleTimeout, 30.0)
        XCTAssertEqual(options.maxIdleStreamsPerPeer, 100)
        XCTAssertNil(options.certificates)
        XCTAssertNil(options.secKey)
    }

    // MARK: - Key Management Tests

    func testKeyManagerInitialization() throws {
        // Test that we can initialize a MobileKeyManager for certificates
        let logger = ConsoleLogger(prefix: "KeyTest")
        let keyManager = try MobileKeyManager(logger: logger)

        // Initialize user root key
        let rootPublicKey = try keyManager.initializeUserRootKey()
        XCTAssertEqual(rootPublicKey.count, 97) // P-384 uncompressed public key

        // Generate CSR
        let setupToken = try keyManager.generateCSR()
        XCTAssertFalse(setupToken.nodeId.isEmpty)
        XCTAssertTrue(setupToken.csrDer.isEmpty) // CSR is now empty, we use public key directly
        XCTAssertEqual(setupToken.nodePublicKey.count, 97)

        // Process the CSR to get a certificate
        let certMessage = try keyManager.processSetupToken(setupToken)
        XCTAssertNotNil(certMessage.nodeCertificate)
        XCTAssertNotNil(certMessage.caCertificate)

        // Get QUIC certificate configuration
        let quicConfig = try keyManager.getQuicCertificateConfig()
        XCTAssertEqual(quicConfig.certificateChain.count, 2) // Node + CA certificates
        // Verify we have a valid SecKey (not checking privateKey anymore)
        XCTAssertNotNil(quicConfig.secKey)
    }

    func testTwoNodeCertificateGeneration() async throws {
        // Test that two nodes can generate certificates independently
        try await runWithTimeout(10.0) {
            print("🚀 Testing two-node certificate generation...")

            // Create two key managers
            let keyManager1 = try MobileKeyManager(logger: ConsoleLogger(prefix: "Node1"))
            let keyManager2 = try MobileKeyManager(logger: ConsoleLogger(prefix: "Node2"))

            // Initialize root keys
            let rootKey1 = try keyManager1.initializeUserRootKey()
            let rootKey2 = try keyManager2.initializeUserRootKey()

            XCTAssertEqual(rootKey1.count, 97)
            XCTAssertEqual(rootKey2.count, 97)
            XCTAssertNotEqual(rootKey1, rootKey2) // Different keys

            // Generate certificates
            let setupToken1 = try keyManager1.generateCSR()
            let setupToken2 = try keyManager2.generateCSR()

            let certMessage1 = try keyManager1.processSetupToken(setupToken1)
            let certMessage2 = try keyManager2.processSetupToken(setupToken2)

            // Verify certificates are different
            XCTAssertNotEqual(setupToken1.nodeId, setupToken2.nodeId)
            XCTAssertNotEqual(certMessage1.nodeCertificate.toDER(), certMessage2.nodeCertificate.toDER())

            // Get QUIC configs
            let quicConfig1 = try keyManager1.getQuicCertificateConfig()
            let quicConfig2 = try keyManager2.getQuicCertificateConfig()

            XCTAssertEqual(quicConfig1.certificateChain.count, 2)
            XCTAssertEqual(quicConfig2.certificateChain.count, 2)
            XCTAssertNotEqual(quicConfig1.secKey, quicConfig2.secKey)

            print("✅ Two-node certificate generation successful!")
            print("   Node 1 ID: \(setupToken1.nodeId)")
            print("   Node 2 ID: \(setupToken2.nodeId)")
            print("   Node 1 cert size: \(certMessage1.nodeCertificate.toDER().count) bytes")
            print("   Node 2 cert size: \(certMessage2.nodeCertificate.toDER().count) bytes")
        }
    }

    // MARK: - End-to-End QUIC Transport Tests

    func testEndToEndQuicTransportWithTLS() async throws {
        // This is the main test that creates two transporters with proper TLS certificates
        // and verifies they can communicate with each other, matching the Rust test coverage

        try await runWithTimeout(testTimeout) {
            print("🚀 Starting comprehensive end-to-end QUIC transport test with TLS certificates...")

            // ==================================================
            // STEP 1: Initialize Certificate Infrastructure (Mobile CA)
            // ==================================================
            print("📋 Step 1: Initializing certificate infrastructure (Mobile CA)...")

            // Create ONE mobile key manager that acts as the CA for both nodes
            let mobileCA = try MobileKeyManager(logger: ConsoleLogger(prefix: "MobileCA"))

            // Initialize user root key and create CA certificate (mobile acts as CA)
            let userRootPublicKey = try mobileCA.initializeUserRootKey()
            try mobileCA.createCACertificate()
            let userCAPublicKey = mobileCA.getCaPublicKey()

            XCTAssertEqual(userRootPublicKey.count, 97) // P-384
            XCTAssertEqual(userCAPublicKey.count, 97) // P-384

            print("✅ Mobile CA initialized with user root and CA keys")

            // ==================================================
            // STEP 2: Setup Node 1 Certificate
            // ==================================================
            print("📋 Step 2: Setting up Node 1 certificate...")

            // Create node 1 key manager and generate setup token
            let nodeKeyManager1 = try MobileKeyManager(logger: ConsoleLogger(prefix: "Node1"))
            _ = try nodeKeyManager1.initializeUserRootKey() // Initialize root key first
            let setupToken1 = try nodeKeyManager1.generateCSR()

            // Mobile CA processes setup token and signs certificate
            let cert1 = try mobileCA.processSetupToken(setupToken1)

            // Node 1 installs the certificate directly
            try nodeKeyManager1.installCertificate(cert1)

            print("✅ Node 1 certificate installed")

            // ==================================================
            // STEP 3: Setup Node 2 Certificate
            // ==================================================
            print("📋 Step 3: Setting up Node 2 certificate...")

            // Create node 2 key manager and generate setup token
            let nodeKeyManager2 = try MobileKeyManager(logger: ConsoleLogger(prefix: "Node2"))
            _ = try nodeKeyManager2.initializeUserRootKey() // Initialize root key first
            let setupToken2 = try nodeKeyManager2.generateCSR()

            // Mobile CA processes setup token and signs certificate
            let cert2 = try mobileCA.processSetupToken(setupToken2)

            // Node 2 installs the certificate directly
            try nodeKeyManager2.installCertificate(cert2)

            print("✅ Node 2 certificate installed")

            // ==================================================
            // STEP 4: Get QUIC Certificates
            // ==================================================
            print("📋 Step 4: Getting QUIC certificates...")

            // NOW both nodes can get QUIC certificates because they have valid certificates
            let node1CertConfig = try nodeKeyManager1.getQuicCertificateConfig()
            let node2CertConfig = try nodeKeyManager2.getQuicCertificateConfig()

            XCTAssertEqual(node1CertConfig.certificateChain.count, 2) // Node + CA certificates
            XCTAssertEqual(node2CertConfig.certificateChain.count, 2) // Node + CA certificates
            XCTAssertNotNil(node1CertConfig.secKey)
            XCTAssertNotNil(node2CertConfig.secKey)

            print("✅ QUIC certificates retrieved for both nodes")

            // ==================================================
            // STEP 5: Get Real Node Public Keys for Proper Peer Identification
            // ==================================================
            print("📋 Step 5: Getting real node public keys...")

            // Get the actual node public keys (not hardcoded values)
            let node1PublicKeyBytes = nodeKeyManager1.getNodePublicKey()
            let node1Id = CryptoUtils.compactId(node1PublicKeyBytes)

            let node2PublicKeyBytes = nodeKeyManager2.getNodePublicKey()
            let node2Id = CryptoUtils.compactId(node2PublicKeyBytes)

            XCTAssertEqual(node1PublicKeyBytes.count, 97) // P-384
            XCTAssertEqual(node2PublicKeyBytes.count, 97) // P-384
            XCTAssertNotEqual(node1Id, node2Id) // Different node IDs

            print("✅ Node 1 ID: \(node1Id)")
            print("✅ Node 2 ID: \(node2Id)")

            // ==================================================
            // STEP 6: Create Message Tracking for Validation
            // ==================================================
            print("📋 Step 6: Setting up message tracking...")

            let node1Messages = MessageTracker()
            let node2Messages = MessageTracker()

            // Create message handlers that track all received messages and return responses
            let node1Handler = TestMessageHandler(
                nodeId: node1Id,
                logger: RunarLogger(subsystem: "com.runar.transporter", category: "Node1"),
                messageTracker: node1Messages
            )

            let node2Handler = TestMessageHandler(
                nodeId: node2Id,
                logger: RunarLogger(subsystem: "com.runar.transporter", category: "Node2"),
                messageTracker: node2Messages
            )

            print("✅ Message tracking setup complete")

            // ==================================================
            // STEP 7: Create Node Info and Transport Options
            // ==================================================
            print("📋 Step 7: Creating node info and transport options...")

            let node1Info = RunarNodeInfo(
                nodePublicKey: node1PublicKeyBytes,
                networkIds: ["test-network"],
                addresses: [self.node1Address],
                services: [
                    ServiceMetadata(
                        servicePath: "/api1",
                        networkId: "test-network",
                        serviceName: "api1",
                        description: "API 1",
                        actions: [
                            ActionMetadata(
                                actionPath: "/api1/get",
                                actionName: "get",
                                description: "GET operation"
                            ),
                            ActionMetadata(
                                actionPath: "/api1/post",
                                actionName: "post",
                                description: "POST operation"
                            ),
                        ],
                        events: [
                            EventMetadata(
                                path: "/api1/data_processed",
                                description: "Data processing completed"
                            ),
                        ]
                    ),
                ]
            )

            let node2Info = RunarNodeInfo(
                nodePublicKey: node2PublicKeyBytes,
                networkIds: ["test-network"],
                addresses: [self.node2Address],
                services: [
                    ServiceMetadata(
                        servicePath: "/storage1",
                        networkId: "test-network",
                        serviceName: "storage1",
                        description: "Storage 1",
                        actions: [
                            ActionMetadata(
                                actionPath: "/storage1/store",
                                actionName: "store",
                                description: "Store operation"
                            ),
                            ActionMetadata(
                                actionPath: "/storage1/retrieve",
                                actionName: "retrieve",
                                description: "Retrieve operation"
                            ),
                        ],
                        events: [
                            EventMetadata(
                                path: "/storage1/storage_updated",
                                description: "Storage state changed"
                            ),
                        ]
                    ),
                ]
            )

            // Create transport options for both nodes
            let node1Options = NetworkQuicTransportOptions(
                verifyCertificates: true,
                keepAliveInterval: 15.0,
                connectionIdleTimeout: 60.0,
                streamIdleTimeout: 30.0,
                maxIdleStreamsPerPeer: 10,
                certificates: node1CertConfig.certificateChain,
                secKey: node1CertConfig.secKey,
                mobileKeyManager: nodeKeyManager1
            )

            let node2Options = NetworkQuicTransportOptions(
                verifyCertificates: true,
                keepAliveInterval: 15.0,
                connectionIdleTimeout: 60.0,
                streamIdleTimeout: 30.0,
                maxIdleStreamsPerPeer: 10,
                certificates: node2CertConfig.certificateChain,
                secKey: node2CertConfig.secKey,
                mobileKeyManager: nodeKeyManager2
            )

            print("✅ Node info and transport options created")

            // ==================================================
            // STEP 8: Initialize Transport Instances
            // ==================================================
            print("📋 Step 8: Initializing transport instances...")

            let echoHandler1 = EchoingHandler(base: node1Handler)
            let echoHandler2 = EchoingHandler(base: node2Handler)
            let transporter1 = NetworkQuicTransporter(
                nodeInfo: node1Info,
                bindAddress: self.node1Address,
                messageHandler: echoHandler1,
                options: node1Options,
                logger: RunarLogger(subsystem: "com.runar.transporter", category: "Transport1")
            )

            let transporter2 = NetworkQuicTransporter(
                nodeInfo: node2Info,
                bindAddress: self.node2Address,
                messageHandler: echoHandler2,
                options: node2Options,
                logger: RunarLogger(subsystem: "com.runar.transporter", category: "Transport2")
            )
            // Wire transporters into echo handlers
            echoHandler1.transporter = transporter1
            echoHandler2.transporter = transporter2

            print("✅ Transport instances initialized")

            // ==================================================
            // STEP 9: Start Transport Services
            // ==================================================
            print("📋 Step 9: Starting transport services...")

            try await transporter1.start()
            try await transporter2.start()

            // Allow transport services to initialize
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            print("✅ Both transport services started")

            // ==================================================
            // STEP 10: Test Connection Management
            // ==================================================
            print("📋 Step 10: Testing connection management...")

            // Convert node info to peer info for connection
            let peerInfo1 = RunarPeerInfo(
                publicKey: node1PublicKeyBytes,
                addresses: [self.node1Address],
                name: "Node1",
                metadata: [:]
            )

            let peerInfo2 = RunarPeerInfo(
                publicKey: node2PublicKeyBytes,
                addresses: [self.node2Address],
                name: "Node2",
                metadata: [:]
            )

            // Force both transports to connect to each other for bidirectional communication
            print("🔗 Establishing bidirectional connections...")
            try await transporter1.connect(to: peerInfo2)
            try await transporter2.connect(to: peerInfo1)

            // Connection readiness is validated by handshake in the next step (to align with Rust flow)
            print("✅ Connection attempts initiated; will validate readiness via handshake")

            // ==================================================
            // STEP 11: Test Handshake Messages
            // ==================================================
            print("📋 Step 11: Testing handshake messages...")

            // Allow time for handshake messages to be exchanged
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            let node1HandshakeMessages = node1Messages.getMessages().filter { $0.messageType == MessageTypes.HANDSHAKE }
            let node2HandshakeMessages = node2Messages.getMessages().filter { $0.messageType == MessageTypes.HANDSHAKE }

            let handshakeReceived = !node1HandshakeMessages.isEmpty || !node2HandshakeMessages.isEmpty

            print("📊 Handshake check - Node1 handshake messages: \(node1HandshakeMessages.count)")
            print("📊 Handshake check - Node2 handshake messages: \(node2HandshakeMessages.count)")
            print("📊 Handshake received: \(handshakeReceived)")

            XCTAssertTrue(handshakeReceived, "Handshake messages should be exchanged")

            print("✅ Handshake working correctly")

            // ==================================================
            // STEP 12: Test Request-Response Messaging
            // ==================================================
            print("📋 Step 12: Testing request-response messaging...")

            let testData = "test_value".data(using: .utf8)!

            let requestMessage = RunarNetworkMessage(
                sourceNodeId: node1Id,
                destinationNodeId: node2Id,
                messageType: "REQUEST",
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "/api1/get",
                        valueBytes: testData,
                        correlationId: "request-1"
                    ),
                ]
            )

            // Send request from node1 to node2
            try await transporter1.send(message: requestMessage)

            // Allow message to be processed
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Check that request was received
            let node2RequestMessages = node2Messages.getMessages().filter { $0.messageType == MessageTypes.REQUEST }
            XCTAssertTrue(!node2RequestMessages.isEmpty, "Node2 should receive request message")

            // Check that response was sent back
            let node1ResponseMessages = node1Messages.getMessages().filter { $0.messageType == MessageTypes.RESPONSE }
            XCTAssertTrue(!node1ResponseMessages.isEmpty, "Node1 should receive response message")

            print("✅ Request-response messaging working correctly")

            // ==================================================
            // STEP 13: Test Event Publishing
            // ==================================================
            print("📋 Step 13: Testing event publishing...")

            let eventData = "event_data".data(using: .utf8)!
            let eventMessage = RunarNetworkMessage(
                sourceNodeId: node1Id,
                destinationNodeId: node2Id,
                messageType: "EVENT",
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "/api1/data_processed",
                        valueBytes: eventData,
                        correlationId: "event-1"
                    ),
                ]
            )

            // Send event from node1 to node2
            try await transporter1.send(message: eventMessage)

            // Allow message to be processed
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Check that event was received
            let node2EventMessages = node2Messages.getMessages().filter { $0.messageType == MessageTypes.EVENT }
            XCTAssertTrue(!node2EventMessages.isEmpty, "Node2 should receive event message")

            print("✅ Event publishing working correctly")

            // STEP 14 skipped: Announcement is not a Rust core message type. Keeping E2E aligned with Rust.

            // ==================================================
            // STEP 15: Comprehensive Analysis
            // ==================================================
            print("📋 Step 15: Comprehensive analysis...")

            let node1AllMessages = node1Messages.getMessages()
            let node2AllMessages = node2Messages.getMessages()

            print("📊 MESSAGE FLOW ANALYSIS:")
            print("  - Node 1 received \(node1AllMessages.count) messages:")
            for (i, msg) in node1AllMessages.enumerated() {
                print("    - \(i): \(msg.messageType) from \(msg.sourceNodeId)")
            }

            print("  - Node 2 received \(node2AllMessages.count) messages:")
            for (i, msg) in node2AllMessages.enumerated() {
                print("    - \(i): \(msg.messageType) from \(msg.sourceNodeId)")
            }

            // Validate different message types
            let hasHandshake = node1AllMessages.contains { $0.messageType == MessageTypes.HANDSHAKE } ||
                node2AllMessages.contains { $0.messageType == MessageTypes.HANDSHAKE }
            let hasRequest = node1AllMessages.contains { $0.messageType == MessageTypes.REQUEST } ||
                node2AllMessages.contains { $0.messageType == MessageTypes.REQUEST }
            let hasResponse = node1AllMessages.contains { $0.messageType == MessageTypes.RESPONSE } ||
                node2AllMessages.contains { $0.messageType == MessageTypes.RESPONSE }
            let hasEvent = node1AllMessages.contains { $0.messageType == MessageTypes.EVENT } ||
                node2AllMessages.contains { $0.messageType == MessageTypes.EVENT }
            let hasAnnouncement = false

            print("📊 MESSAGE TYPE VALIDATION:")
            print("  - Handshake: \(hasHandshake)")
            print("  - Request: \(hasRequest)")
            print("  - Response: \(hasResponse)")
            print("  - Event: \(hasEvent)")
            print("  - Announcement: \(hasAnnouncement)")

            // Validate at least some messages were exchanged
            XCTAssertTrue(!node1AllMessages.isEmpty || !node2AllMessages.isEmpty, "At least one node should have received messages")

            // Validate different message types were processed
            XCTAssertTrue(hasRequest && hasResponse, "Request and response messages should be processed")
            XCTAssertTrue(hasEvent, "Event messages should be processed")
            // Announcement intentionally skipped for Rust alignment

            print("✅ Comprehensive analysis completed")

            // ==================================================
            // STEP 16: Cleanup
            // ==================================================
            print("📋 Step 16: Cleaning up...")
            await transporter1.stop()
            await transporter2.stop()

            print("🎉 Comprehensive end-to-end QUIC transport test with TLS completed successfully!")
        }
    }

    func testBasicAsyncOperationsWithTimeout() async throws {
        // Test basic async operations with timeout
        try await runWithTimeout(2.0) {
            // Simple async operation that should complete quickly
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            XCTAssertTrue(true) // Just verify we can complete async operations
        }
    }

    func testTimeoutMechanism() async throws {
        // Test that timeout mechanism actually works
        do {
            try await runWithTimeout(0.1) {
                // This should timeout
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                return "should not reach here"
            }
            XCTFail("Should have timed out")
        } catch let error as TestTimeoutError {
            // Expected timeout
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testComprehensiveCertificateInfrastructure() async throws {
        // This test demonstrates the complete certificate infrastructure working correctly
        // without the QUIC transport SecIdentity limitations

        try await runWithTimeout(15.0) {
            print("🚀 Testing comprehensive certificate infrastructure...")

            // ==================================================
            // STEP 1: Initialize Certificate Infrastructure (Mobile CA)
            // ==================================================
            print("📋 Step 1: Initializing certificate infrastructure (Mobile CA)...")

            // Create ONE mobile key manager that acts as the CA for both nodes
            let mobileCA = try MobileKeyManager(logger: ConsoleLogger(prefix: "MobileCA"))

            // Initialize user root key and create CA certificate (mobile acts as CA)
            let userRootPublicKey = try mobileCA.initializeUserRootKey()
            try mobileCA.createCACertificate()
            let userCAPublicKey = mobileCA.getCaPublicKey()

            XCTAssertEqual(userRootPublicKey.count, 97) // P-384
            XCTAssertEqual(userCAPublicKey.count, 97) // P-384

            print("✅ Mobile CA initialized with user root and CA keys")
            print("   Root key: \(userRootPublicKey.count) bytes")
            print("   CA key: \(userCAPublicKey.count) bytes")

            // ==================================================
            // STEP 2: Setup Node 1 Certificate
            // ==================================================
            print("📋 Step 2: Setting up Node 1 certificate...")

            // Create node 1 key manager and generate setup token
            let nodeKeyManager1 = try MobileKeyManager(logger: ConsoleLogger(prefix: "Node1"))
            _ = try nodeKeyManager1.initializeUserRootKey() // Initialize root key first
            let setupToken1 = try nodeKeyManager1.generateCSR()

            // Mobile CA processes setup token and signs certificate
            let cert1 = try mobileCA.processSetupToken(setupToken1)

            // Node 1 installs the certificate directly
            try nodeKeyManager1.installCertificate(cert1)

            print("✅ Node 1 certificate installed")
            print("   Node 1 ID: \(setupToken1.nodeId)")
            print("   CSR size: \(setupToken1.csrDer.count) bytes")

            // ==================================================
            // STEP 3: Setup Node 2 Certificate
            // ==================================================
            print("📋 Step 3: Setting up Node 2 certificate...")

            // Create node 2 key manager and generate setup token
            let nodeKeyManager2 = try MobileKeyManager(logger: ConsoleLogger(prefix: "Node2"))
            _ = try nodeKeyManager2.initializeUserRootKey() // Initialize root key first
            let setupToken2 = try nodeKeyManager2.generateCSR()

            // Mobile CA processes setup token and signs certificate
            let cert2 = try mobileCA.processSetupToken(setupToken2)

            // Node 2 installs the certificate directly
            try nodeKeyManager2.installCertificate(cert2)

            print("✅ Node 2 certificate installed")
            print("   Node 2 ID: \(setupToken2.nodeId)")
            print("   CSR size: \(setupToken2.csrDer.count) bytes")

            // ==================================================
            // STEP 4: Get QUIC Certificates
            // ==================================================
            print("📋 Step 4: Getting QUIC certificates...")

            // NOW both nodes can get QUIC certificates because they have valid certificates
            let node1CertConfig = try nodeKeyManager1.getQuicCertificateConfig()
            let node2CertConfig = try nodeKeyManager2.getQuicCertificateConfig()

            XCTAssertEqual(node1CertConfig.certificateChain.count, 2) // Node + CA certificates
            XCTAssertEqual(node2CertConfig.certificateChain.count, 2) // Node + CA certificates
            XCTAssertNotNil(node1CertConfig.secKey)
            XCTAssertNotNil(node2CertConfig.secKey)

            print("✅ QUIC certificates retrieved for both nodes")
            print("   Node 1 cert chain: \(node1CertConfig.certificateChain.count) certificates")
            print("   Node 2 cert chain: \(node2CertConfig.certificateChain.count) certificates")
            print("   Node 1 SecKey: Available")
            print("   Node 2 SecKey: Available")

            // ==================================================
            // STEP 5: Get Real Node Public Keys for Proper Peer Identification
            // ==================================================
            print("📋 Step 5: Getting real node public keys...")

            // Get the actual node public keys (not hardcoded values)
            let node1PublicKeyBytes = nodeKeyManager1.getNodePublicKey()
            let node1Id = CryptoUtils.compactId(node1PublicKeyBytes)

            let node2PublicKeyBytes = nodeKeyManager2.getNodePublicKey()
            let node2Id = CryptoUtils.compactId(node2PublicKeyBytes)

            XCTAssertEqual(node1PublicKeyBytes.count, 97) // P-384
            XCTAssertEqual(node2PublicKeyBytes.count, 97) // P-384
            XCTAssertNotEqual(node1Id, node2Id) // Different node IDs
            XCTAssertNotEqual(setupToken1.nodeId, setupToken2.nodeId) // Different setup tokens

            print("✅ Node public keys retrieved")
            print("   Node 1 public key: \(node1PublicKeyBytes.count) bytes")
            print("   Node 2 public key: \(node2PublicKeyBytes.count) bytes")
            print("   Node 1 compact ID: \(node1Id)")
            print("   Node 2 compact ID: \(node2Id)")

            // ==================================================
            // STEP 6: Validate Certificate Chain
            // ==================================================
            print("📋 Step 6: Validating certificate chain...")

            // Validate that certificates are different
            let node1CertData = cert1.nodeCertificate.toDER()
            let node2CertData = cert2.nodeCertificate.toDER()

            XCTAssertNotEqual(node1CertData, node2CertData, "Node certificates should be different")
            XCTAssertGreaterThan(node1CertData.count, 500, "Node certificates should be substantial size")
            XCTAssertGreaterThan(node2CertData.count, 500, "Node certificates should be substantial size")

            print("✅ Certificate chain validation passed")
            print("   Node 1 cert size: \(node1CertData.count) bytes")
            print("   Node 2 cert size: \(node2CertData.count) bytes")

            // ==================================================
            // STEP 7: Test Certificate Authority Functions
            // ==================================================
            print("📋 Step 7: Testing certificate authority functions...")

            // Test CA certificate retrieval
            let caCert = mobileCA.getCaCertificate()
            let caCertData = caCert.toDER()

            XCTAssertFalse(caCertData.isEmpty, "CA certificate should not be empty")
            XCTAssertGreaterThan(caCertData.count, 100, "CA certificate should be substantial size")

            // Test certificate status
            let certStatus1 = nodeKeyManager1.getCertificateStatus()
            let certStatus2 = nodeKeyManager2.getCertificateStatus()

            XCTAssertEqual(certStatus1, .valid, "Node 1 should have valid certificate status")
            XCTAssertEqual(certStatus2, .valid, "Node 2 should have valid certificate status")

            print("✅ Certificate authority functions working")
            print("   CA certificate size: \(caCertData.count) bytes")
            print("   Node 1 cert status: \(certStatus1)")
            print("   Node 2 cert status: \(certStatus2)")

            // ==================================================
            // STEP 8: Test Key Management Functions
            // ==================================================
            print("📋 Step 8: Testing key management functions...")

            // Test profile key generation
            let profileKey1 = try nodeKeyManager1.deriveUserProfileKey(label: "personal")
            let profileKey2 = try nodeKeyManager2.deriveUserProfileKey(label: "work")

            XCTAssertEqual(profileKey1.count, 97) // P-384 public key size
            XCTAssertEqual(profileKey2.count, 97) // P-384 public key size
            XCTAssertNotEqual(profileKey1, profileKey2, "Profile keys should be different")

            // Test storage key generation
            let storageKey1 = nodeKeyManager1.getStorageKey()
            let storageKey2 = nodeKeyManager2.getStorageKey()

            XCTAssertEqual(storageKey1.count, 32) // AES-256 key size
            XCTAssertEqual(storageKey2.count, 32) // AES-256 key size
            XCTAssertNotEqual(storageKey1, storageKey2, "Storage keys should be different")

            print("✅ Key management functions working")
            print("   Profile key 1 size: \(profileKey1.count) bytes")
            print("   Profile key 2 size: \(profileKey2.count) bytes")
            print("   Storage key 1 size: \(storageKey1.count) bytes")
            print("   Storage key 2 size: \(storageKey2.count) bytes")

            // ==================================================
            // STEP 9: Comprehensive Validation
            // ==================================================
            print("📋 Step 9: Comprehensive validation...")

            // Validate that all components are working together
            XCTAssertNotEqual(node1Id, node2Id, "Node IDs should be different")
            XCTAssertNotEqual(setupToken1.nodeId, setupToken2.nodeId, "Setup token IDs should be different")
            XCTAssertNotEqual(node1CertData, node2CertData, "Certificates should be different")
            XCTAssertNotEqual(node1CertConfig.secKey, node2CertConfig.secKey, "Private keys should be different")
            XCTAssertNotEqual(profileKey1, profileKey2, "Profile keys should be different")
            XCTAssertNotEqual(storageKey1, storageKey2, "Storage keys should be different")

            print("✅ Comprehensive validation passed")
            print("🎉 Certificate infrastructure test completed successfully!")
            print("")
            print("📊 SUMMARY:")
            print("   ✅ Mobile CA initialized with P-384 keys")
            print("   ✅ Node 1 certificate chain created (\(node1CertData.count) bytes)")
            print("   ✅ Node 2 certificate chain created (\(node2CertData.count) bytes)")
            print("   ✅ QUIC certificate configs ready for transport")
            print("   ✅ All keys are unique and properly sized")
            print("   ✅ Certificate authority functions working")
            print("   ✅ Key management functions working")
            print("")
            print("🚀 Ready for QUIC transport integration!")
        }
    }
}

// MARK: - Helper Classes

/// Message tracker for testing
private class MessageTracker {
    private var messages: [RunarNetworkMessage] = []
    private let queue = DispatchQueue(label: "com.runar.test.messagetracker", qos: .userInitiated)

    func addMessage(_ message: RunarNetworkMessage) {
        queue.sync {
            messages.append(message)
        }
    }

    func getMessages() -> [RunarNetworkMessage] {
        queue.sync {
            messages
        }
    }

    func clear() {
        queue.sync {
            messages.removeAll()
        }
    }
}

/// Simple message handler for testing
private class SimpleMessageHandler: MessageHandlerProtocol {
    func handleMessage(_ message: RunarNetworkMessage) {
        // Simple implementation for testing
        print("Handled message: \(message.messageType)")
    }

    func peerConnected(_ peerInfo: RunarNodeInfo) {
        print("Peer connected: \(peerInfo.nodeId)")
    }

    func peerDisconnected(_ peerId: String) {
        print("Peer disconnected: \(peerId)")
    }
}

/// Test message handler that tracks received messages
private class TestMessageHandler: MessageHandlerProtocol {
    private let nodeId: String
    private let logger: RunarLogger
    private let messageTracker: MessageTracker
    private(set) var receivedMessages: [RunarNetworkMessage] = []
    private(set) var connectedPeers: [RunarNodeInfo] = []
    private(set) var disconnectedPeers: [String] = []

    init(nodeId: String, logger: RunarLogger, messageTracker: MessageTracker) {
        self.nodeId = nodeId
        self.logger = logger
        self.messageTracker = messageTracker
    }

    func handleMessage(_ message: RunarNetworkMessage) {
        logger.info("📨 [\(nodeId)] Received message: \(message.messageType) from \(message.sourceNodeId)")
        receivedMessages.append(message)
        messageTracker.addMessage(message)

        // Echo back a response for request/response testing
        if message.messageType == "RequestMessage" {
            let response = RunarNetworkMessage(
                sourceNodeId: nodeId,
                destinationNodeId: message.sourceNodeId,
                messageType: "ResponseMessage",
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "/api/response",
                        valueBytes: "Response data".data(using: .utf8)!,
                        correlationId: message.payloads.first?.correlationId ?? "unknown"
                    ),
                ]
            )

            // Note: In a real implementation, we would send this response back
            // For now, we just log it
            logger.info("📤 [\(nodeId)] Would send response: \(response.messageType)")
        }
    }

    func peerConnected(_ peerInfo: RunarNodeInfo) {
        logger.info("🔗 [\(nodeId)] Peer connected: \(peerInfo.nodeId)")
        connectedPeers.append(peerInfo)
    }

    func peerDisconnected(_ peerId: String) {
        logger.info("🔌 [\(nodeId)] Peer disconnected: \(peerId)")
        disconnectedPeers.append(peerId)
    }
}

/// Wrapper handler that echoes a RESPONSE for each REQUEST using correlation id
private final class EchoingHandler: MessageHandlerProtocol {
    private let base: MessageHandlerProtocol
    weak var transporter: TransportProtocol?
    init(base: MessageHandlerProtocol) { self.base = base }
    func handleMessage(_ message: RunarNetworkMessage) {
        base.handleMessage(message)
        if message.messageType == MessageTypes.REQUEST,
           let corr = message.payloads.first?.correlationId
        {
            let response = RunarNetworkMessage(
                sourceNodeId: message.destinationNodeId,
                destinationNodeId: message.sourceNodeId,
                messageType: MessageTypes.RESPONSE,
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "echo",
                        valueBytes: message.payloads.first?.valueBytes ?? Data(),
                        correlationId: corr
                    ),
                ]
            )
            Task { try? await transporter?.send(message: response) }
        }
    }

    func peerConnected(_ peerInfo: RunarNodeInfo) { base.peerConnected(peerInfo) }
    func peerDisconnected(_ peerId: String) { base.peerDisconnected(peerId) }
}

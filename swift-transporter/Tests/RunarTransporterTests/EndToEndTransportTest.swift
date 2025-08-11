import XCTest
import SwiftCommon
import RunarKeys
@testable import RunarTransporter

@available(macOS 12.0, iOS 15.0, *)
final class EndToEndTransportTest: XCTestCase {
    
    private var transport1: NetworkQuicTransporter!
    private var transport2: NetworkQuicTransporter!
    private var logger: RunarLogger!
    private var node1PublicKey: Data!
    private var node2PublicKey: Data!
    private var node1Id: String!
    private var node2Id: String!
    private var nodeKeyManager1: MobileKeyManager!
    private var nodeKeyManager2: MobileKeyManager!
    
    // Message tracking for validation
    private var transport1Messages: [RunarNetworkMessage] = []
    private var transport2Messages: [RunarNetworkMessage] = []
    
    override func setUp() async throws {
        logger = RunarLogger(subsystem: "com.runar.transporter.test", category: "E2ETest")
        
        // Create message handlers that track received messages
        let handler1 = TestMessageHandler { [weak self] message in
            self?.transport1Messages.append(message)
        }
        
        let handler2 = TestMessageHandler { [weak self] message in
            self?.transport2Messages.append(message)
        }
        
        // Prepare certificate infrastructure: one CA and two nodes
        let mobileCA = try MobileKeyManager(logger: ConsoleLogger(prefix: "E2E-CA"))
        _ = try mobileCA.initializeUserRootKey()
        try mobileCA.createCACertificate()
        
        nodeKeyManager1 = try MobileKeyManager(logger: ConsoleLogger(prefix: "E2E-Node1"))
        _ = try nodeKeyManager1.initializeUserRootKey()
        let setupToken1 = try nodeKeyManager1.generateCSR()
        let cert1 = try mobileCA.processSetupToken(setupToken1)
        try nodeKeyManager1.installCertificate(cert1)
        
        nodeKeyManager2 = try MobileKeyManager(logger: ConsoleLogger(prefix: "E2E-Node2"))
        _ = try nodeKeyManager2.initializeUserRootKey()
        let setupToken2 = try nodeKeyManager2.generateCSR()
        let cert2 = try mobileCA.processSetupToken(setupToken2)
        try nodeKeyManager2.installCertificate(cert2)
        
        // Compute real node public keys and ids
        node1PublicKey = nodeKeyManager1.getNodePublicKey()
        node2PublicKey = nodeKeyManager2.getNodePublicKey()
        node1Id = CryptoUtils.compactId(node1PublicKey)
        node2Id = CryptoUtils.compactId(node2PublicKey)
        
        // Create node info for both transports
        let node1Info = RunarNodeInfo(
            nodePublicKey: node1PublicKey,
            addresses: ["127.0.0.1:50069"],
            services: []
        )
        
        let node2Info = RunarNodeInfo(
            nodePublicKey: node2PublicKey,
            addresses: ["127.0.0.1:50044"],
            services: []
        )
        
        // Create transport options including certificates and SecKey
        let node1CertConfig = try nodeKeyManager1.getQuicCertificateConfig()
        let node2CertConfig = try nodeKeyManager2.getQuicCertificateConfig()
        
        let options1 = NetworkQuicTransportOptions(
            verifyCertificates: true,
            keepAliveInterval: 15.0,
            connectionIdleTimeout: 60.0,
            streamIdleTimeout: 30.0,
            maxIdleStreamsPerPeer: 10,
            certificates: node1CertConfig.certificateChain,
            secKey: node1CertConfig.secKey,
            mobileKeyManager: nodeKeyManager1
        )
        let options2 = NetworkQuicTransportOptions(
            verifyCertificates: true,
            keepAliveInterval: 15.0,
            connectionIdleTimeout: 60.0,
            streamIdleTimeout: 30.0,
            maxIdleStreamsPerPeer: 10,
            certificates: node2CertConfig.certificateChain,
            secKey: node2CertConfig.secKey,
            mobileKeyManager: nodeKeyManager2
        )
        
        // Initialize transports
        transport1 = NetworkQuicTransporter(
            nodeInfo: node1Info,
            bindAddress: "127.0.0.1:50069",
            messageHandler: handler1,
            options: options1,
            logger: logger
        )
        
        transport2 = NetworkQuicTransporter(
            nodeInfo: node2Info,
            bindAddress: "127.0.0.1:50044", 
            messageHandler: handler2,
            options: options2,
            logger: logger
        )
    }
    
    override func tearDown() async throws {
        await transport1?.stop()
        await transport2?.stop()
        transport1 = nil
        transport2 = nil
    }
    
    func testEndToEndTransportCommunication() async throws {
        try await runWithTimeout(20) {
            self.logger.info("🚀 Starting E2E transport test")
            
            // Step 0: Test message encoding/decoding works correctly
            self.logger.info("🔧 Testing message encoding/decoding...")
            let testMessage = RunarNetworkMessage(
                sourceNodeId: self.node1Id,
                destinationNodeId: self.node2Id,
                messageType: MessageTypes.REQUEST,
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "test:api1/get",
                        valueBytes: "test_value".data(using: .utf8)!,
                        correlationId: "test-request-1"
                    )
                ]
            )
            
            do {
                let encoded = try BinaryMessageEncoder.encodeNetworkMessage(testMessage)
                let decoded = try BinaryMessageEncoder.decodeNetworkMessage(from: encoded)
                XCTAssertEqual(decoded.sourceNodeId, testMessage.sourceNodeId)
                XCTAssertEqual(decoded.destinationNodeId, testMessage.destinationNodeId)
                XCTAssertEqual(decoded.messageType, testMessage.messageType)
                XCTAssertEqual(decoded.payloads.count, testMessage.payloads.count)
                self.logger.info("✅ Message encoding/decoding test passed - encoded size: \(encoded.count) bytes")
            } catch {
                self.logger.error("❌ Message encoding/decoding test failed: \(error)")
                throw error
            }
            
            // Step 1: Start both transports
            self.logger.info("📡 Starting transport services...")
            try await self.transport1.start()
            try await self.transport2.start()
            
            // Allow transports to initialize
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Step 2: Connect transports to each other
            self.logger.info("🔗 Connecting transports...")
            
            let peer1Info = RunarPeerInfo(
                publicKey: self.node1PublicKey,
                addresses: ["127.0.0.1:50069"]
            )
            
            let peer2Info = RunarPeerInfo(
                publicKey: self.node2PublicKey,
                addresses: ["127.0.0.1:50044"]
            )
            
            // Connect both directions for bidirectional communication
            try await self.transport1.connect(to: peer2Info)
            try await self.transport2.connect(to: peer1Info)
            
            // Allow connections to establish
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Step 3: Verify connections
            let t1Connected = await self.transport1.isConnected(to: self.node2Id)
            let t2Connected = await self.transport2.isConnected(to: self.node1Id)
            
            self.logger.info("🔍 Connection status: T1→T2=\(t1Connected), T2→T1=\(t2Connected)")
            
            XCTAssertTrue(t1Connected && t2Connected, "Both connections should be established")
            
            // Step 4: Test handshake
            self.logger.info("🤝 Testing handshake...")
            
            // Wait for handshake messages to be processed
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            let handshakeReceived = self.transport1Messages.contains { $0.messageType == MessageTypes.HANDSHAKE } ||
                                   self.transport2Messages.contains { $0.messageType == MessageTypes.HANDSHAKE }
            
            XCTAssertTrue(handshakeReceived, "Handshake messages should be exchanged")
            
            // Step 5: Test request-response messaging
            self.logger.info("🔄 Testing request-response messaging...")
            
            let testData = "test_value".data(using: .utf8)!
            let requestMessage = RunarNetworkMessage(
                sourceNodeId: self.node1Id,
                destinationNodeId: self.node2Id,
                messageType: MessageTypes.REQUEST,
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "test:api1/get",
                        valueBytes: testData,
                        correlationId: "test-request-1"
                    )
                ]
            )
            
            // Send request
            try await self.transport1.send(message: requestMessage)
            
            // Allow message processing
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Verify request was received
            let requestReceived = self.transport2Messages.contains { $0.messageType == MessageTypes.REQUEST }
            XCTAssertTrue(requestReceived, "Request message should be received")
            
            // Step 6: Test event publishing
            self.logger.info("📡 Testing event publishing...")
            
            let eventData = "event_data".data(using: .utf8)!
            let eventMessage = RunarNetworkMessage(
                sourceNodeId: self.node1Id,
                destinationNodeId: self.node2Id,
                messageType: MessageTypes.EVENT,
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "test:api1/data_processed",
                        valueBytes: eventData,
                        correlationId: "event-\(UUID().uuidString)"
                    )
                ]
            )
            
            try await self.transport1.send(message: eventMessage)
            
            // Allow message processing
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Verify event was received
            let eventReceived = self.transport2Messages.contains { $0.messageType == MessageTypes.EVENT }
            XCTAssertTrue(eventReceived, "Event message should be received")
            
            // Step 7: Test announcement messages
            self.logger.info("📢 Testing announcement messages...")
            
            let announcementData = "Test announcement data".data(using: .utf8)!
            let announcementMessage = RunarNetworkMessage(
                sourceNodeId: self.node1Id,
                destinationNodeId: self.node2Id,
                messageType: MessageTypes.ANNOUNCEMENT,
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "",
                        valueBytes: announcementData,
                        correlationId: "announcement_test"
                    )
                ]
            )
            
            try await self.transport1.send(message: announcementMessage)
            
            // Allow message processing
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Verify announcement was received
            let announcementReceived = self.transport2Messages.contains { $0.messageType == MessageTypes.ANNOUNCEMENT }
            XCTAssertTrue(announcementReceived, "Announcement message should be received")
            
            // Step 8: Test bidirectional messaging
            self.logger.info("🔄 Testing bidirectional messaging...")
            
            let responseData = "Response from Node2".data(using: .utf8)!
            let responseMessage = RunarNetworkMessage(
                sourceNodeId: self.node2Id,
                destinationNodeId: self.node1Id,
                messageType: MessageTypes.RESPONSE,
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "test:api1/get",
                        valueBytes: responseData,
                        correlationId: "test-request-1"
                    )
                ]
            )
            
            try await self.transport2.send(message: responseMessage)
            
            // Allow message processing
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Verify response was received
            let responseReceived = self.transport1Messages.contains { $0.messageType == MessageTypes.RESPONSE }
            XCTAssertTrue(responseReceived, "Response message should be received")
            
            // Step 9: Final validation
            self.logger.info("✅ E2E test completed successfully")
            
            // Verify we have messages from both directions
            XCTAssertFalse(self.transport1Messages.isEmpty, "Transport1 should have received messages")
            XCTAssertFalse(self.transport2Messages.isEmpty, "Transport2 should have received messages")
            
            // Log message counts
            self.logger.info("📊 Final message counts - Transport1: \(self.transport1Messages.count), Transport2: \(self.transport2Messages.count)")
            
            // Verify different message types were processed
            let messageTypes1 = Set(self.transport1Messages.map { $0.messageType })
            let messageTypes2 = Set(self.transport2Messages.map { $0.messageType })
            
            self.logger.info("📊 Message types - Transport1: \(messageTypes1), Transport2: \(messageTypes2)")
            
            XCTAssertTrue(messageTypes1.count > 0, "Transport1 should have processed different message types")
            XCTAssertTrue(messageTypes2.count > 0, "Transport2 should have processed different message types")
        }
    }
}

// MARK: - Test Message Handler

@available(macOS 12.0, iOS 15.0, *)
private class TestMessageHandler: MessageHandlerProtocol {
    private let messageCallback: (RunarNetworkMessage) -> Void
    
    init(messageCallback: @escaping (RunarNetworkMessage) -> Void) {
        self.messageCallback = messageCallback
    }
    
    func handleMessage(_ message: RunarNetworkMessage) {
        messageCallback(message)
    }
    
    func peerConnected(_ peerInfo: RunarNodeInfo) {
        // Track peer connections if needed
    }
    
    func peerDisconnected(_ peerId: String) {
        // Track peer disconnections if needed
    }
}

 
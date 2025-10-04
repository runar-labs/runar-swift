import SwiftCBOR
import SwiftCommon
import SwiftFFI
import XCTest

/// Tests for peer connection functionality with the new NodeInfo API
final class PeerConnectionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset global config for each test
        LoggerConfigManager.shared.globalConfig = LoggerConfig(level: .info)
    }

    /// Test that peer connection callbacks receive the correct NodeInfo data
    func testPeerConnectionWithNodeInfo() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("testPeerConnectionWithNodeInfo"))

        // Create two key managers
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Create mobile key manager for CA (Certificate Authority)
        let keysCA = try await MobileKeyManager()

        // Set node info for both nodes
        let nodeInfo = NodeInfo(
            nodePublicKey: Data(),
            networkIds: ["test_network"],
            addresses: ["127.0.0.1:0"],
            nodeMetadata: NodeMetadata(services: [], subscriptions: []),
            version: 1
        )
        let nodeInfoCbor = try CodableCBOREncoder().encode(nodeInfo)

        // Note: NodeInfo is now set on the transport, not on keys
        // This will be set when creating the transport

        // Generate CSR for node A and process through mobile CA
        let csrA = try await keysA.generateCsrSetupToken(logger: logger.child(component: .network))
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        // Generate CSR for node B and process through mobile CA
        let csrB = try await keysB.generateCsrSetupToken(logger: logger.child(component: .network))
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)

        // Create transport options
        let transportOptions = QuicTransportOptions(
            requestTimeoutSeconds: 30,
            bindAddr: "127.0.0.1:0"
        )

        // Create expectations for peer connection events
        let peerConnectedExpectation = expectation(description: "Peer connected with NodeInfo")
        let peerDisconnectedExpectation = expectation(description: "Peer disconnected")

        // Track received NodeInfo
        let receivedNodeInfo = Box<NodeInfo?>(nil)
        let receivedPeerId = Box<String?>(nil)

        // Create transport A with peer connection callbacks
        let callbacksA = TransportCallbacks(
            peerConnectedCallback: { peerId, nodeInfo in
                print("PeerConnectionTests - Peer connected: \(peerId)")
                print("PeerConnectionTests - NodeInfo: \(nodeInfo)")

                Task {
                    await receivedPeerId.setValue(peerId)
                    await receivedNodeInfo.setValue(nodeInfo)
                    peerConnectedExpectation.fulfill()
                }
            },
            peerDisconnectedCallback: { peerId in
                print("PeerConnectionTests - Peer disconnected: \(peerId)")
                peerDisconnectedExpectation.fulfill()
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

        let loggerA = RunarLogger.root(component: .custom("PeerConnectionTests"))
        let localNodeInfo = NodeInfo(
            nodePublicKey: Data(),
            networkIds: ["test_network"],
            addresses: ["127.0.0.1:0"],
            nodeMetadata: NodeMetadata(services: [], subscriptions: []),
            version: 1
        )
        let transportA = try await QuicTransport.create(keys: keysA, nodeInfo: localNodeInfo, options: transportOptions, callbacks: callbacksA, logger: loggerA)
        try await transportA.setLocalNodeInfo(nodeInfoCbor)
        try await transportA.start()

        // Create transport B with minimal callbacks
        let callbacksB = TransportCallbacks(
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
        let loggerB = RunarLogger.root(component: .custom("PeerConnectionTests"))
        let transportB = try await QuicTransport.create(keys: keysB, nodeInfo: localNodeInfo, options: transportOptions, callbacks: callbacksB, logger: loggerB)
        try await transportB.setLocalNodeInfo(nodeInfoCbor)
        try await transportB.start()

        // Get local address for transport A
        let localAddrA = try await transportA.getLocalAddr()
        XCTAssertFalse(localAddrA.isEmpty, "Local address should not be empty")

        // Get public key for node A
        let publicKeyA = try await keysA.getNodePublicKey()

        // Generate peer ID using compact ID
        let peerIdA = try await keysA.getCompactId(for: publicKeyA)

        // Create peer info for connection
        let peerInfo = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])

        // Connect transport B to transport A
        try await transportB.connectPeer(peerInfo: peerInfo)

        // Wait for peer connection
        await fulfillment(of: [peerConnectedExpectation], timeout: 10.0)

        // Verify that we received the correct peer ID and NodeInfo
        let receivedPeerIdValue = await receivedPeerId.value
        let receivedNodeInfoValue = await receivedNodeInfo.value

        XCTAssertNotNil(receivedPeerIdValue, "Should have received peer ID")
        XCTAssertNotNil(receivedNodeInfoValue, "Should have received NodeInfo")

        if let peerId = receivedPeerIdValue {
            // Peer ID should not be empty and should be a valid format
            XCTAssertFalse(peerId.isEmpty, "Peer ID should not be empty")
            XCTAssertTrue(peerId.count > 10, "Peer ID should be reasonably long")
        }

        if let nodeInfo = receivedNodeInfoValue {
            // Verify NodeInfo structure
            XCTAssertFalse(nodeInfo.networkIds.isEmpty, "NodeInfo should have network IDs")
            XCTAssertFalse(nodeInfo.addresses.isEmpty, "NodeInfo should have addresses")
            XCTAssertNotNil(nodeInfo.nodeMetadata, "NodeInfo should have metadata")
            XCTAssertGreaterThan(nodeInfo.version, 0, "NodeInfo should have valid version")

            // Note: nodePublicKey might be empty in test environment, so we don't assert on it
            // The important thing is that we received a valid NodeInfo structure
        }

        // Stop transport B to trigger disconnection
        try await transportB.stop()

        // Wait for peer disconnection
        await fulfillment(of: [peerDisconnectedExpectation], timeout: 5.0)

        // Clean up
        try await transportA.stop()
    }

    /// Test that HandshakeData can be properly serialized and deserialized
    func testHandshakeDataSerialization() throws {
        // Create a sample NodeInfo
        let nodeInfo = NodeInfo(
            nodePublicKey: Data("test-public-key".utf8),
            networkIds: ["network1", "network2"],
            addresses: ["127.0.0.1:8080", "192.168.1.1:8080"],
            nodeMetadata: NodeMetadata(
                services: [
                    ServiceMetadata(
                        networkId: "network1",
                        servicePath: "math1/add",
                        name: "Math Service",
                        version: "1.0.0",
                        description: "Basic math operations",
                        actions: [],
                        registrationTime: 1_234_567_890,
                        lastStartTime: 1_234_567_890
                    ),
                ],
                subscriptions: [
                    SubscriptionMetadata(path: "math1/*"),
                ]
            ),
            version: 1
        )

        // Create HandshakeData
        let handshakeData = HandshakeData(
            nodeInfo: nodeInfo,
            nonce: 12345,
            role: .initiator
        )

        // Test serialization
        let encoder = CodableCBOREncoder()
        let encodedData = try encoder.encode(handshakeData)
        XCTAssertFalse(encodedData.isEmpty, "Encoded data should not be empty")

        // Test deserialization
        let decoder = CodableCBORDecoder()
        let decodedHandshakeData = try decoder.decode(HandshakeData.self, from: encodedData)

        // Verify all fields match
        XCTAssertEqual(decodedHandshakeData.nodeInfo.nodePublicKey, handshakeData.nodeInfo.nodePublicKey)
        XCTAssertEqual(decodedHandshakeData.nodeInfo.networkIds, handshakeData.nodeInfo.networkIds)
        XCTAssertEqual(decodedHandshakeData.nodeInfo.addresses, handshakeData.nodeInfo.addresses)
        XCTAssertEqual(decodedHandshakeData.nodeInfo.version, handshakeData.nodeInfo.version)
        XCTAssertEqual(decodedHandshakeData.nonce, handshakeData.nonce)
        XCTAssertEqual(decodedHandshakeData.role, handshakeData.role)
    }

    /// Test that ConnectionRole enum works correctly
    func testConnectionRole() {
        // Test initiator role
        let initiator = ConnectionRole.initiator
        XCTAssertEqual(initiator.rawValue, "Initiator")

        // Test responder role
        let responder = ConnectionRole.responder
        XCTAssertEqual(responder.rawValue, "Responder")

        // Test serialization
        let encoder = CodableCBOREncoder()
        let initiatorData = try! encoder.encode(initiator)
        let responderData = try! encoder.encode(responder)

        XCTAssertFalse(initiatorData.isEmpty)
        XCTAssertFalse(responderData.isEmpty)

        // Test deserialization
        let decoder = CodableCBORDecoder()
        let decodedInitiator = try! decoder.decode(ConnectionRole.self, from: initiatorData)
        let decodedResponder = try! decoder.decode(ConnectionRole.self, from: responderData)

        XCTAssertEqual(decodedInitiator, initiator)
        XCTAssertEqual(decodedResponder, responder)
    }

    // TransportEvent test removed - replaced with typed event structs
}

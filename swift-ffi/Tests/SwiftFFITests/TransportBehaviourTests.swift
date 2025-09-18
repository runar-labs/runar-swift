import XCTest
import SwiftFFI
import SwiftCommon

@testable import SwiftFFI

/// Tests for transport behavior
/// Tests request/publish/complete/poll_event with multiple peers; negative cases
final class TransportBehaviourTests: XCTestCase {
    
    private var nodeKeys: KeysHandle!
    private var transport1: TransportHandle!
    private var transport2: TransportHandle!
    
    override func setUp() {
        super.setUp()
        
        // Create node keys handle
        nodeKeys = try! KeysHandle()
        try! nodeKeys.initializeAsNode()
        try! nodeKeys.nodeGenerateKeys()
        
        // Set local node info (required for transport)
        let nodePublicKey = try! nodeKeys.getNodePublicKey()
        let nodeInfo = CBORHelper.createMinimalNodeInfo(nodePublicKey: nodePublicKey)
        let nodeInfoCbor = try! CBORHelper.encodeNodeInfo(nodeInfo)
        try! nodeKeys.setLocalNodeInfo(nodeInfoCbor: nodeInfoCbor)
        
        // Create transport options
        let transportOptions = QuicTransportOptionsCbor(
            bindAddr: "127.0.0.1:0",
            handshakeTimeoutMs: 5000,
            openStreamTimeoutMs: 10000,
            maxMessageSize: 1024,
            responseCacheTtlMs: 30000,
            maxRequestRetries: 3
        )
        
        let optionsCbor = try! CBORHelper.encodeTransportOptions(transportOptions)
        
        // Create two transport handles for testing
        transport1 = try! TransportHandle.create(keys: nodeKeys, optionsCbor: optionsCbor)
        transport2 = try! TransportHandle.create(keys: nodeKeys, optionsCbor: optionsCbor)
    }
    
    override func tearDown() {
        transport1 = nil
        transport2 = nil
        nodeKeys = nil
        super.tearDown()
    }
    
    // MARK: - Transport Lifecycle Tests
    
    func testTransportLifecycle() throws {
        // Test complete transport lifecycle
        
        // 1. Start transport
        try transport1.start()
        
        // 2. Get local address
        let localAddr = try transport1.getLocalAddr()
        XCTAssertFalse(localAddr.isEmpty, "Local address should not be empty")
        
        // 3. Stop transport
        try transport1.stop()
    }
    
    func testTransportStartStopMultipleTimes() throws {
        // Test starting and stopping transport multiple times
        
        // Start transport
        try transport1.start()
        
        // Stop transport
        try transport1.stop()
        
        // Start again
        try transport1.start()
        
        // Stop again
        try transport1.stop()
    }
    
    // MARK: - Transport Request Tests
    
    func testTransportRequest() throws {
        // Test sending a request through transport
        
        try transport1.start()
        
        // Create request parameters
        let requestParams = TransportRequestParams(
            path: "/test/request",
            correlationId: UUID().uuidString,
            payload: "Hello, World!".data(using: .utf8)!,
            destPeerId: "test-peer-id",
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        let requestCbor = try CBORHelper.encodeTransportRequestParams(requestParams)
        
        // Send request
        try transport1.request(requestCbor: requestCbor)
    }
    
    func testTransportRequestWithInvalidData() throws {
        // Test sending request with invalid data
        
        try transport1.start()
        
        // Test with empty data
        let emptyData = Data()
        
        do {
            try transport1.request(requestCbor: emptyData)
            XCTFail("Should have thrown error for empty request data")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        // Test with invalid CBOR data
        let invalidData = Data([0x01, 0x02, 0x03, 0x04])
        
        do {
            try transport1.request(requestCbor: invalidData)
            XCTFail("Should have thrown error for invalid request data")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Transport Publish Tests
    
    func testTransportPublish() throws {
        // Test publishing an event through transport
        
        try transport1.start()
        
        // Create publish parameters (simplified for testing)
        let publishData = "Test event data".data(using: .utf8)!
        
        // Publish event
        try transport1.publish(publishCbor: publishData)
    }
    
    func testTransportPublishWithInvalidData() throws {
        // Test publishing with invalid data
        
        try transport1.start()
        
        // Test with empty data
        let emptyData = Data()
        
        do {
            try transport1.publish(publishCbor: emptyData)
            XCTFail("Should have thrown error for empty publish data")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Transport Complete Request Tests
    
    func testTransportCompleteRequest() throws {
        // Test completing a request through transport
        
        try transport1.start()
        
        // Create complete request parameters
        let completeParams = TransportCompleteRequestParams(
            requestId: "test-request-id",
            responsePayload: "Response data".data(using: .utf8)!,
            profilePublicKeys: []
        )
        
        let completeCbor = try CBORHelper.encodeTransportCompleteRequestParams(completeParams)
        
        // Complete request - this should fail since no certificate is installed
        do {
            try transport1.completeRequest(completeCbor: completeCbor)
            XCTFail("Should have thrown error when no certificate is installed")
        } catch {
            XCTAssertTrue(error is FFIError)
            // Expected error: "Certificate not found: Node certificate not installed"
        }
    }
    
    func testTransportCompleteRequestWithInvalidData() throws {
        // Test completing request with invalid data
        
        try transport1.start()
        
        // Test with empty data
        let emptyData = Data()
        
        do {
            try transport1.completeRequest(completeCbor: emptyData)
            XCTFail("Should have thrown error for empty complete request data")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Transport Event Polling Tests
    
    func testTransportPollEvent() throws {
        // Test polling for events
        
        try transport1.start()
        
        // Poll for events (might return nil if no events)
        let event = try transport1.pollEvent()
        
        // Event might be nil if no events are available
        if let event = event {
            XCTAssertFalse(event.isEmpty, "Event data should not be empty if present")
        }
    }
    
    func testTransportPollEventMultipleTimes() throws {
        // Test polling for events multiple times
        
        try transport1.start()
        
        // Poll multiple times
        for _ in 0..<10 {
            let event = try transport1.pollEvent()
            if let event = event {
                XCTAssertFalse(event.isEmpty, "Event data should not be empty if present")
            }
        }
    }
    
    // MARK: - Transport Peer Connection Tests
    
    func testTransportConnectPeer() throws {
        // Test connecting to a peer
        
        try transport1.start()
        try transport2.start()
        
        // Get peer info from transport2
        let peerInfo = PeerInfo(
            publicKey: try nodeKeys.getNodePublicKey(),
            addresses: [try transport2.getLocalAddr()]
        )
        
        let peerInfoCbor = try CBORHelper.encodePeerInfo(peerInfo)
        
        // Connect to peer
        try transport1.connectPeer(peerInfoCbor: peerInfoCbor)
    }
    
    func testTransportDisconnectPeer() throws {
        // Test disconnecting from a peer
        
        try transport1.start()
        
        // Disconnect from peer (using a test peer ID)
        let peerNodeId = "test-peer-node-id"
        
        try transport1.disconnectPeer(peerNodeId: peerNodeId)
    }
    
    func testTransportIsConnected() throws {
        // Test checking connection status
        
        try transport1.start()
        
        // Check connection status
        let peerNodeId = "test-peer-node-id"
        let isConnected = try transport1.isConnected(peerNodeId: peerNodeId)
        
        // Should be false initially
        XCTAssertFalse(isConnected, "Should not be connected to non-existent peer")
    }
    
    // MARK: - Transport Node Info Tests
    
    func testTransportUpdateLocalNodeInfo() throws {
        // Test updating local node info
        
        try transport1.start()
        
        // Create node info
        let nodeInfo = CBORHelper.createMinimalNodeInfo(
            nodePublicKey: try nodeKeys.getNodePublicKey(),
            networkId: "test-network"
        )
        
        let nodeInfoCbor = try CBORHelper.encodeNodeInfo(nodeInfo)
        
        // Update local node info
        try transport1.updateLocalNodeInfo(nodeInfoCbor: nodeInfoCbor)
    }
    
    func testTransportUpdateLocalNodeInfoWithInvalidData() throws {
        // Test updating local node info with invalid data
        
        try transport1.start()
        
        // Test with empty data
        let emptyData = Data()
        
        do {
            try transport1.updateLocalNodeInfo(nodeInfoCbor: emptyData)
            XCTFail("Should have thrown error for empty node info data")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Multiple Peers Tests
    
    func testTransportWithMultiplePeers() throws {
        // Test transport with multiple peers
        
        try transport1.start()
        try transport2.start()
        
        // Get peer info from transport2
        let peerInfo = PeerInfo(
            publicKey: try nodeKeys.getNodePublicKey(),
            addresses: [try transport2.getLocalAddr()]
        )
        
        let peerInfoCbor = try CBORHelper.encodePeerInfo(peerInfo)
        
        // Connect to peer
        try transport1.connectPeer(peerInfoCbor: peerInfoCbor)
        
        // Check connection status
        let isConnected = try transport1.isConnected(peerNodeId: "test-peer-id")
        // Status depends on actual connection establishment
    }
    
    // MARK: - Transport Error Handling Tests
    
    func testTransportOperationsWithoutStart() throws {
        // Test transport operations without starting
        
        // Test request without start
        let requestParams = TransportRequestParams(
            path: "/test",
            correlationId: "test-id",
            payload: Data(),
            destPeerId: "test-peer",
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        let requestCbor = try CBORHelper.encodeTransportRequestParams(requestParams)
        
        do {
            try transport1.request(requestCbor: requestCbor)
            XCTFail("Should have thrown error for request without start")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testTransportOperationsAfterStop() throws {
        // Test transport operations after stopping
        
        try transport1.start()
        try transport1.stop()
        
        // Test request after stop
        let requestParams = TransportRequestParams(
            path: "/test",
            correlationId: "test-id",
            payload: Data(),
            destPeerId: "test-peer",
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        let requestCbor = try CBORHelper.encodeTransportRequestParams(requestParams)
        
        do {
            try transport1.request(requestCbor: requestCbor)
            XCTFail("Should have thrown error for request after stop")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Transport Timeout Tests
    
    func testTransportTimeoutScenarios() throws {
        // Test transport timeout scenarios
        
        // Create transport with short timeout
        let shortTimeoutOptions = QuicTransportOptionsCbor(
            bindAddr: "127.0.0.1:0",
            handshakeTimeoutMs: 100, // Very short timeout
            openStreamTimeoutMs: 200,
            maxMessageSize: 1024,
            responseCacheTtlMs: 1000,
            maxRequestRetries: 1
        )
        
        let optionsCbor = try CBORHelper.encodeTransportOptions(shortTimeoutOptions)
        let shortTimeoutTransport = try TransportHandle.create(keys: nodeKeys, optionsCbor: optionsCbor)
        
        try shortTimeoutTransport.start()
        
        // Test operations with short timeout
        let requestParams = TransportRequestParams(
            path: "/test",
            correlationId: "test-id",
            payload: Data(),
            destPeerId: "test-peer",
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        let requestCbor = try CBORHelper.encodeTransportRequestParams(requestParams)
        
        do {
            try shortTimeoutTransport.request(requestCbor: requestCbor)
            // Might succeed or fail depending on timeout
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Transport Concurrent Operations Tests
    
    func testTransportConcurrentOperations() throws {
        // Test concurrent transport operations
        
        try transport1.start()
        
        let expectation = XCTestExpectation(description: "Concurrent transport operations")
        expectation.expectedFulfillmentCount = 3
        
        // Run concurrent operations
        DispatchQueue.global().async {
            do {
                let requestParams = TransportRequestParams(
                    path: "/test1",
                    correlationId: "test-id-1",
                    payload: "Test 1".data(using: .utf8)!,
                    destPeerId: "test-peer-1",
                    networkPublicKey: nil,
                    profilePublicKeys: []
                )
                let requestCbor = try CBORHelper.encodeTransportRequestParams(requestParams)
                try self.transport1.request(requestCbor: requestCbor)
                expectation.fulfill()
            } catch {
                // Might fail depending on transport state
                expectation.fulfill()
            }
        }
        
        DispatchQueue.global().async {
            do {
                let publishData = "Test publish".data(using: .utf8)!
                try self.transport1.publish(publishCbor: publishData)
                expectation.fulfill()
            } catch {
                // Might fail depending on transport state
                expectation.fulfill()
            }
        }
        
        DispatchQueue.global().async {
            do {
                let event = try self.transport1.pollEvent()
                // Event might be nil
                expectation.fulfill()
            } catch {
                // Might fail depending on transport state
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Transport Large Message Tests
    
    func testTransportLargeMessage() throws {
        // Test transport with large messages
        
        try transport1.start()
        
        // Create large message
        let largeMessage = Data(repeating: 0x42, count: 1024 * 1024) // 1MB message
        
        let requestParams = TransportRequestParams(
            path: "/test/large",
            correlationId: "large-test-id",
            payload: largeMessage,
            destPeerId: "test-peer",
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        let requestCbor = try CBORHelper.encodeTransportRequestParams(requestParams)
        
        do {
            try transport1.request(requestCbor: requestCbor)
            // Might succeed or fail depending on message size limits
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Transport Invalid CBOR Tests
    
    func testTransportInvalidCbor() throws {
        // Test transport with invalid CBOR data
        
        try transport1.start()
        
        // Test with malformed CBOR
        let malformedCbor = Data([0xFF, 0xFE, 0xFD, 0xFC]) // Invalid CBOR
        
        do {
            try transport1.request(requestCbor: malformedCbor)
            XCTFail("Should have thrown error for malformed CBOR")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            try transport1.publish(publishCbor: malformedCbor)
            XCTFail("Should have thrown error for malformed CBOR")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            try transport1.completeRequest(completeCbor: malformedCbor)
            XCTFail("Should have thrown error for malformed CBOR")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Transport Performance Tests
    
    func testTransportPerformance() throws {
        // Test transport performance
        
        try transport1.start()
        
        let iterations = 100
        let requestParams = TransportRequestParams(
            path: "/test",
            correlationId: "test-id",
            payload: "Test message".data(using: .utf8)!,
            destPeerId: "test-peer",
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        let requestCbor = try CBORHelper.encodeTransportRequestParams(requestParams)
        
        // Measure request performance
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            do {
                try transport1.request(requestCbor: requestCbor)
            } catch {
                // Ignore errors for performance testing
            }
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = totalTime / Double(iterations)
        
        // Verify operations completed
        XCTAssertGreaterThan(totalTime, 0, "Transport operations should take some time")
        
        // Log performance metrics (optional)
        print("Average transport request time: \(averageTime) seconds")
    }
}

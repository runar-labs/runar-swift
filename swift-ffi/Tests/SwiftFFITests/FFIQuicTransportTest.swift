import SwiftCBOR
import SwiftCommon
import SwiftFFI
import XCTest

/// Comprehensive QUIC Transport Integration Tests
///
/// This test mirrors the Rust ffi_transport_test.rs exactly to validate
/// the complete QUIC transport functionality including:
/// - Certificate generation and installation
/// - Transport creation and connection
/// - Request/response patterns
/// - Event handling
/// - Connection state management
///
/// NOTE: This test uses the improved Transport API with callbacks but still matches
/// the Rust test in all rules, steps, setup and asserts. It does not compromise
/// the test - it just uses the new callback-based API instead of manual polling.
@testable import SwiftFFI

// Use the TransportEvent from SwiftFFI instead of defining our own

/// Thread-safe box for capturing values in callbacks
final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@MainActor
final class FFIQuicTransportTest: XCTestCase {
    
    /// Test two transports request/response - exactly matching Rust two_transports_request_response
    /// This is the main test that validates the complete transport functionality
    func testTwoTransportsRequestResponse() async throws {
        // Set up logging to match Rust test
        try await FFILogger.setLogLevel(.trace)
        try await FFILogger.setLoggerNodeId("two-transports-test")
        
        // Step 1: Create two node key managers (A and B) - exactly like Rust
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()
        
        // Step 2: Create mobile key manager for CA (Certificate Authority) - exactly like Rust
        let keysCA = try await MobileKeyManager()
        
        // Step 3: Set node info for both nodes - exactly like Rust
        let nodeInfo = CBORHelper.createMinimalNodeInfo(nodePublicKey: Data())
        let nodeInfoCbor = try await CBORHelper.encodeNodeInfo(nodeInfo)
        
        try await keysA.setLocalNodeInfo(nodeInfoCbor)
        try await keysB.setLocalNodeInfo(nodeInfoCbor)
        
        // Step 4: Generate CSR for node A and process through mobile CA - exactly like Rust
        let csrA = try await keysA.generateCsrSetupToken()
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)
        
        // Step 5: Generate CSR for node B and process through mobile CA - exactly like Rust
        let csrB = try await keysB.generateCsrSetupToken()
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)
        
        // Step 6: Create transport options - exactly like Rust
        let transportOptions = CBORHelper.createMinimalTransportOptions(bindAddr: "127.0.0.1:0")
        
        // Step 7: Set up callbacks for transport A (request handler) - exactly like Rust
        let requestReceived = expectation(description: "Request received on transport A")
        let requestIdBox = Box<String?>(nil)
        
        let callbacksA = TransportCallbacks(
            requestCallback: { receivedRequestId, path, payload, sourcePeerId, correlationId in
                requestIdBox.value = receivedRequestId
                requestReceived.fulfill()
                return Data("world".utf8) // Return response for this test
            }
        )
        
        // Step 8: Create transport A and start it - exactly like Rust
        let loggerA = RunarLogger(component: .custom)
        let transportA = try await QuicTransport.create(keys: keysA, options: transportOptions, callbacks: callbacksA, logger: loggerA)
        try await transportA.start()
        
        // Step 9: Get local address for transport A - exactly like Rust
        let localAddrA = try await transportA.getLocalAddr()
        XCTAssertFalse(localAddrA.isEmpty, "Local address should not be empty")
        
        // Step 10: Set up callbacks for transport B (no special callbacks needed) - exactly like Rust
        let callbacksB = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in return nil }
        )
        
        // Step 11: Create transport B and start it - exactly like Rust
        let loggerB = RunarLogger(component: .custom)
        let transportB = try await QuicTransport.create(keys: keysB, options: transportOptions, callbacks: callbacksB, logger: loggerB)
        try await transportB.start()
        
        // Step 12: Get public key for node A - exactly like Rust
        let publicKeyA = try await keysA.getNodePublicKey()
        
        // Step 13: Generate peer ID using compact ID (matching Rust implementation) - exactly like Rust
        let peerId = try await keysA.getCompactId(for: publicKeyA)
        
        // Step 14: Create peer info for connection - exactly like Rust
        let peerInfo = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])
        
        // Step 15: Connect transport B to transport A - exactly like Rust
        try await transportB.connectPeer(peerInfo: peerInfo)
        
        // Step 16: Create request parameters - exactly like Rust
        let requestParams = TransportRequestParams(
            path: "/echo",
            correlationId: "c1",
            payload: Data("hello".utf8),
            destPeerId: peerId,
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        // Step 17: Send request from transport B and wait for response - exactly like Rust
        // The request() method should handle the response internally and return it
        let responseData = try await transportB.request(requestParams)
        
        // Step 18: Wait for request to be received on A - exactly like Rust
        await fulfillment(of: [requestReceived], timeout: 5.0)
        XCTAssertNotNil(requestIdBox.value, "Should have received request on transport A")
        
        // Step 19: Verify response was received - exactly like Rust
        // The response should be the data returned by the request() method
        XCTAssertEqual(responseData, Data("world".utf8), "Should have received correct response data")
        
        // Step 21: Cleanup - exactly like Rust
        try await transportA.stop()
        try await transportB.stop()
    }
    
    /// Test transport start/stop idempotence - exactly matching Rust test_transport_start_stop_idempotence
    func testTransportStartStopIdempotence() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerNodeId("idempotence-test")
        
        // Create keys for the transport
        let keys = try await NodeKeyManager()
        
        // Create mobile key manager for CA
        let keysCA = try await MobileKeyManager()
        
        // Set node info
        let nodeInfo = CBORHelper.createMinimalNodeInfo(nodePublicKey: Data())
        let nodeInfoCbor = try await CBORHelper.encodeNodeInfo(nodeInfo)
        try await keys.setLocalNodeInfo(nodeInfoCbor)
        
        // Generate CSR and install certificate
        let csr = try await keys.generateCsrSetupToken()
        let cert = try await keysCA.processSetupToken(csr)
        try await keys.installCertificate(cert)
        
        // Create transport options
        let transportOptions = CBORHelper.createMinimalTransportOptions(bindAddr: "127.0.0.1:0")
        
        // Create transport
        let callbacks = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in return nil }
        )
        let logger = RunarLogger(component: .custom)
        let transport = try await QuicTransport.create(keys: keys, options: transportOptions, callbacks: callbacks, logger: logger)
        
        // Test start/stop idempotence - multiple starts should not fail
        try await transport.start()
        try await transport.start() // Second start should be idempotent
        
        // Test stop/start cycle
        try await transport.stop()
        try await transport.start()
        
        // Test multiple stops should not fail
        try await transport.stop()
        try await transport.stop() // Second stop should be idempotent
        
        // Final cleanup
        try await transport.stop()
    }
    
    /// Test basic transport connection - exactly matching Rust test_basic_transport_connection
    func testBasicTransportConnection() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerNodeId("connection-test")
        
        // Create two node key managers (A and B)
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()
        
        // Create mobile key manager for CA
        let keysCA = try await MobileKeyManager()
        
        // Set node info for both nodes
        let nodeInfo = CBORHelper.createMinimalNodeInfo(nodePublicKey: Data())
        let nodeInfoCbor = try await CBORHelper.encodeNodeInfo(nodeInfo)
        
        try await keysA.setLocalNodeInfo(nodeInfoCbor)
        try await keysB.setLocalNodeInfo(nodeInfoCbor)
        
        // Generate CSR for node A
        let csrA = try await keysA.generateCsrSetupToken()
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)
        
        // Generate CSR for node B
        let csrB = try await keysB.generateCsrSetupToken()
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)
        
        // Create transport options
        let transportOptions = CBORHelper.createMinimalTransportOptions(bindAddr: "127.0.0.1:0")
        
        // Create transport A
        let callbacksA = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in return nil }
        )
        let loggerA = RunarLogger(component: .custom)
        let transportA = try await QuicTransport.create(keys: keysA, options: transportOptions, callbacks: callbacksA, logger: loggerA)
        try await transportA.start()
        
        // Get local address for transport A
        let localAddrA = try await transportA.getLocalAddr()
        XCTAssertFalse(localAddrA.isEmpty, "Local address should not be empty")
        
        // Create transport B
        let callbacksB = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in return nil }
        )
        let loggerB = RunarLogger(component: .custom)
        let transportB = try await QuicTransport.create(keys: keysB, options: transportOptions, callbacks: callbacksB, logger: loggerB)
        try await transportB.start()
        
        // Get public key for node A
        let publicKeyA = try await keysA.getNodePublicKey()
        
        // Generate peer ID using compact ID
        let peerId = try await keysA.getCompactId(for: publicKeyA)
        
        // Create peer info for connection
        let peerInfo = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])
        
        // Connect transport B to transport A
        try await transportB.connectPeer(peerInfo: peerInfo)
        
        // Wait for connection to establish
        try await Task.sleep(nanoseconds: UInt64(100 * 1_000_000)) // 100ms
        
        // Check if connection is established
        let isConnected = try await transportB.isConnected(peerNodeId: peerId)
        XCTAssertTrue(isConnected, "Transport B should be connected to transport A")
        
        // Cleanup
        try await transportA.stop()
        try await transportB.stop()
    }
    
    /// Test basic transport setup - exactly matching Rust test_basic_transport_setup
    func testBasicTransportSetup() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerNodeId("setup-test")
        
        // Create node key manager
        let keys = try await NodeKeyManager()
        
        // Create mobile key manager for CA
        let keysCA = try await MobileKeyManager()
        
        // Set node info
        let nodeInfo = CBORHelper.createMinimalNodeInfo(nodePublicKey: Data())
        let nodeInfoCbor = try await CBORHelper.encodeNodeInfo(nodeInfo)
        try await keys.setLocalNodeInfo(nodeInfoCbor)
        
        // Generate CSR and install certificate
        let csr = try await keys.generateCsrSetupToken()
        let cert = try await keysCA.processSetupToken(csr)
        try await keys.installCertificate(cert)
        
        // Create transport options
        let transportOptions = CBORHelper.createMinimalTransportOptions(bindAddr: "127.0.0.1:0")
        
        // Create transport
        let callbacks = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in return nil }
        )
        let logger = RunarLogger(component: .custom)
        let transport = try await QuicTransport.create(keys: keys, options: transportOptions, callbacks: callbacks, logger: logger)
        XCTAssertNotNil(transport, "Transport should be created successfully")
        
        // Start transport
        try await transport.start()
        
        // Get local address
        let localAddr = try await transport.getLocalAddr()
        XCTAssertFalse(localAddr.isEmpty, "Local address should not be empty")
        
        // Stop transport
        try await transport.stop()
    }
}
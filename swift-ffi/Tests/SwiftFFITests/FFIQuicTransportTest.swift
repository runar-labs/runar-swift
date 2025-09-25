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
@testable import SwiftFFI

// Use the TransportEvent from SwiftFFI instead of defining our own

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
        
        // Step 7: Create transport A and start it - exactly like Rust
        let transportA = try await QuicTransport.create(keys: keysA, options: transportOptions)
        try await transportA.start()
        
        // Step 8: Get local address for transport A - exactly like Rust
        let localAddrA = try await transportA.getLocalAddr()
        XCTAssertFalse(localAddrA.isEmpty, "Local address should not be empty")
        
        // Step 9: Create transport B and start it - exactly like Rust
        let transportB = try await QuicTransport.create(keys: keysB, options: transportOptions)
        try await transportB.start()
        
        // Step 10: Get public key for node A - exactly like Rust
        let publicKeyA = try await keysA.getNodePublicKey()
        
        // Step 11: Generate peer ID using compact ID (matching Rust implementation) - exactly like Rust
        let peerId = try await keysA.getCompactId(for: publicKeyA)
        
        // Step 12: Create peer info for connection - exactly like Rust
        let peerInfo = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])
        
        // Step 13: Connect transport B to transport A - exactly like Rust
        try await transportB.connectPeer(peerInfo: peerInfo)
        
        // Step 14: Create request parameters - exactly like Rust
        let requestParams = TransportRequestParams(
            path: "/echo",
            correlationId: "c1",
            payload: Data("hello".utf8),
            destPeerId: peerId,
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        // Step 15: Send request from transport B - exactly like Rust
        try await transportB.request(requestParams)
        
        // Step 16: Handle request on A then complete - exactly like Rust
        var requestId: String? = nil
        for _ in 0..<50 {
            if let event = try await transportA.pollEvent() {
                if event.type == "RequestReceived" {
                    requestId = event.requestId
                    break
                }
            }
            try await Task.sleep(nanoseconds: UInt64(50 * 1_000_000)) // 50ms like Rust
        }
        
        XCTAssertNotNil(requestId, "Should have received request on transport A")
        
        // Step 17: Complete the request on transport A - exactly like Rust
        let completeParams = TransportCompleteRequestParams(
            requestId: requestId!,
            responsePayload: Data("world".utf8),
            profilePublicKeys: []
        )
        
        try await transportA.completeRequest(completeParams)
        
        // Step 18: Expect response on B - exactly like Rust
        var gotResponse = false
        for _ in 0..<50 {
            if let event = try await transportB.pollEvent() {
                if event.type == "ResponseReceived" {
                    gotResponse = true
                    break
                }
            }
            try await Task.sleep(nanoseconds: UInt64(50 * 1_000_000)) // 50ms like Rust
        }
        
        XCTAssertTrue(gotResponse, "Should have received response on transport B")
        
        // Step 19: Cleanup - exactly like Rust
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
        let transport = try await QuicTransport.create(keys: keys, options: transportOptions)
        
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
        let transportA = try await QuicTransport.create(keys: keysA, options: transportOptions)
        try await transportA.start()
        
        // Get local address for transport A
        let localAddrA = try await transportA.getLocalAddr()
        XCTAssertFalse(localAddrA.isEmpty, "Local address should not be empty")
        
        // Create transport B
        let transportB = try await QuicTransport.create(keys: keysB, options: transportOptions)
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
        let transport = try await QuicTransport.create(keys: keys, options: transportOptions)
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
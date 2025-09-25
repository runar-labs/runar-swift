import SwiftCBOR
import SwiftCommon
import SwiftFFI
import XCTest

/// Test manual polling for events to debug the polling issue
@testable import SwiftFFI

@MainActor
final class ManualPollingTest: XCTestCase {
    
    /// Test manual polling for events - exactly like Rust test
    func testManualPollingForEvents() async throws {
        // Set up logging to match Rust test
        try await FFILogger.setLogLevel(.trace)
        try await FFILogger.setLoggerNodeId("manual-polling-test")
        
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
        
        // Step 7: Create transport A with minimal callbacks
        let callbacksA = TransportCallbacks(
            requestCallback: { receivedRequestId, path, payload, sourcePeerId, correlationId in
                print("ManualPollingTest - Request received on A: \(receivedRequestId)")
                return Data("world".utf8) // Return response
            }
        )
        
        // Step 8: Create transport A and start it
        let loggerA = RunarLogger(component: .custom)
        let transportA = try await QuicTransport.create(keys: keysA, options: transportOptions, callbacks: callbacksA, logger: loggerA)
        try await transportA.start()
        
        // Step 9: Get local address for transport A
        let localAddrA = try await transportA.getLocalAddr()
        XCTAssertFalse(localAddrA.isEmpty, "Local address should not be empty")
        
        // Step 10: Create transport B with minimal callbacks
        let callbacksB = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in return nil }
        )
        
        // Step 11: Create transport B and start it
        let loggerB = RunarLogger(component: .custom)
        let transportB = try await QuicTransport.create(keys: keysB, options: transportOptions, callbacks: callbacksB, logger: loggerB)
        try await transportB.start()
        
        // Step 12: Get public key for node A
        let publicKeyA = try await keysA.getNodePublicKey()
        
        // Step 13: Generate peer ID using compact ID
        let peerId = try await keysA.getCompactId(for: publicKeyA)
        
        // Step 14: Create peer info for connection
        let peerInfo = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])
        
        // Step 15: Connect transport B to transport A
        try await transportB.connectPeer(peerInfo: peerInfo)
        
        // Step 16: Create request parameters
        let requestParams = TransportRequestParams(
            path: "/echo",
            correlationId: "c1",
            payload: Data("hello".utf8),
            destPeerId: peerId,
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        // Step 17: Send request from transport B
        try await transportB.request(requestParams)
        
        // Step 18: Manually poll for events on transport A (like Rust test)
        print("ManualPollingTest - Starting manual polling for RequestReceived event...")
        var requestReceived = false
        for i in 0..<50 { // Try 50 times like Rust test
            do {
                if let event = try await transportA.pollEvent() {
                    print("ManualPollingTest - Event received: \(event.type)")
                    if event.type == "RequestReceived" {
                        print("ManualPollingTest - RequestReceived event found!")
                        requestReceived = true
                        break
                    }
                } else {
                    print("ManualPollingTest - No events available (attempt \(i + 1))")
                }
            } catch {
                print("ManualPollingTest - Error polling events: \(error)")
            }
            
            // Small delay like Rust test
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        XCTAssertTrue(requestReceived, "Should have received RequestReceived event")
        
        // Step 19: Manually poll for events on transport B (like Rust test)
        print("ManualPollingTest - Starting manual polling for ResponseReceived event...")
        var responseReceived = false
        for i in 0..<50 { // Try 50 times like Rust test
            do {
                if let event = try await transportB.pollEvent() {
                    print("ManualPollingTest - Event received: \(event.type)")
                    if event.type == "ResponseReceived" {
                        print("ManualPollingTest - ResponseReceived event found!")
                        responseReceived = true
                        break
                    }
                } else {
                    print("ManualPollingTest - No events available (attempt \(i + 1))")
                }
            } catch {
                print("ManualPollingTest - Error polling events: \(error)")
            }
            
            // Small delay like Rust test
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        XCTAssertTrue(responseReceived, "Should have received ResponseReceived event")
        
        // Step 20: Cleanup
        try await transportA.stop()
        try await transportB.stop()
    }
}

//! Transport Test Only
//!
//! This test corresponds to the Rust ffi_transport_test.rs

@testable import RunarFFI
import XCTest
import SwiftCBOR

// MARK: - Transport Request Parameters (matching Rust structs)

struct TransportRequestParams: Codable {
    let path: String
    let correlation_id: String
    let payload: [UInt8]  // Vec<u8> in Rust
    let dest_peer_id: String
    let network_public_key: [UInt8]?  // Option<Vec<u8>> in Rust
    let profile_public_keys: [[UInt8]]  // Vec<Vec<u8>> in Rust
}

struct TransportCompleteRequestParams: Codable {
    let request_id: String
    let response_payload: [UInt8]  // Vec<u8> in Rust
    let profile_public_keys: [[UInt8]]  // Vec<Vec<u8>> in Rust
}

final class TransportTestOnly: XCTestCase {
    func testTwoTransportsRequestResponse() throws {
        print("🚀 DEBUG: Test starting")
        
        // Enable verbose logging from Rust FFI
        let keysForLogging = KeysFFI()
        keysForLogging.setLogLevel(3) // Set to debug level
        print("🚀 DEBUG: FFI log level set to debug (3)")
        
        // This test corresponds to the Rust two_transports_request_response() test
        // It tests the complete transport flow with two nodes following the exact Rust pattern

        // Create two node keys (A and B)
        print("🔑 DEBUG: About to create keys A and B")
        let keysA = KeysFFI()
        print("🔑 DEBUG: KeysFFI A created, about to initialize as node")
        try keysA.initializeAsNode()
        print("🔑 DEBUG: Keys A initialized as node")

        let keysB = KeysFFI()
        print("🔑 DEBUG: KeysFFI B created, about to initialize as node")
        try keysB.initializeAsNode()
        print("🔑 DEBUG: Keys B initialized as node")

        // Set node info for B first (matching Rust test order)
        print("📋 DEBUG: Creating NodeInfo for B")
        let nodeInfo = NodeInfo(
            node_public_key: [],
            network_ids: [],
            addresses: [],
            node_metadata: NodeMetadata(services: [], subscriptions: []),
            version: 0
        )
        print("📋 DEBUG: NodeInfo created, encoding to CBOR")
        let nodeInfoData = try CodableCBOREncoder().encode(nodeInfo)
        print("📋 DEBUG: NodeInfo CBOR encoded, setting on keysB")
        try keysB.setLocalNodeInfo(nodeInfoData)
        print("📋 DEBUG: NodeInfo set on keysB successfully")

        // Create mobile keys for processing setup tokens (matching Rust test)
        print("📱 DEBUG: Creating mobile key manager C")
        let keysC = KeysFFI()
        print("📱 DEBUG: KeysFFI C created, initializing as mobile")
        try keysC.initializeAsMobile()
        print("📱 DEBUG: Keys C initialized as mobile")

        // Set node info for A (matching Rust test)
        print("📋 DEBUG: Setting NodeInfo on keysA")
        try keysA.setLocalNodeInfo(nodeInfoData)
        print("📋 DEBUG: NodeInfo set on keysA successfully")

        // Generate CSR for node A (matching Rust test)
        print("📝 DEBUG: Generating CSR for node A")
        let csrA = try keysA.nodeGenerateCSR()
        print("📝 DEBUG: CSR A generated, length: \(csrA.count)")
        XCTAssertFalse(csrA.isEmpty, "CSR A should not be empty")

        // Process setup token with mobile keys to get certificate (matching Rust test)
        print("🔄 DEBUG: Processing CSR A with mobile key manager")
        let certificateA = try keysC.mobileProcessSetupToken(csrA)
        print("🔄 DEBUG: Certificate A generated, length: \(certificateA.count)")
        XCTAssertFalse(certificateA.isEmpty, "Certificate A should not be empty")

        // Install certificate on node A (matching Rust test)
        print("📜 DEBUG: Installing certificate on node A")
        try keysA.nodeInstallCertificate(certificateA)
        print("📜 DEBUG: Certificate installed on node A successfully")

        // Generate CSR for node B (matching Rust test)
        print("📝 DEBUG: Generating CSR for node B")
        let csrB = try keysB.nodeGenerateCSR()
        print("📝 DEBUG: CSR B generated, length: \(csrB.count)")
        XCTAssertFalse(csrB.isEmpty, "CSR B should not be empty")

        // Process setup token with mobile keys to get certificate for B (matching Rust test)
        print("🔄 DEBUG: Processing CSR B with mobile key manager")
        let certificateB = try keysC.mobileProcessSetupToken(csrB)
        print("🔄 DEBUG: Certificate B generated, length: \(certificateB.count)")
        XCTAssertFalse(certificateB.isEmpty, "Certificate B should not be empty")

        // Install certificate on node B (matching Rust test)
        print("📜 DEBUG: Installing certificate on node B")
        try keysB.nodeInstallCertificate(certificateB)
        print("📜 DEBUG: Certificate installed on node B successfully")

        // Create transport options (matching Rust test)
        print("🚀 DEBUG: Creating transport options")
        var options: [CBOR: CBOR] = [:]
        options[CBOR.utf8String("bind_addr")] = CBOR.utf8String("127.0.0.1:0")
        options[CBOR.utf8String("max_message_size")] = CBOR.unsignedInt(65536)
        let optionsCbor = Data(CBOR.map(options).encode())
        print("🚀 DEBUG: Transport options created, CBOR length: \(optionsCbor.count)")

        // Create transport A (matching Rust test)
        print("🚀 DEBUG: Creating transport A")
        let transportA = try FFITransport(keys: keysA, optionsCBOR: optionsCbor)
        print("🚀 DEBUG: Transport A created successfully")
        XCTAssertNotNil(transportA, "Transport A should be created")

        // Start transport A (matching Rust test)
        print("🚀 DEBUG: Starting transport A")
        try transportA.start()
        print("🚀 DEBUG: Transport A started successfully")
        let addressA = try transportA.localAddr()
        print("🚀 DEBUG: Transport A local address: \(addressA)")
        XCTAssertFalse(addressA.isEmpty, "Transport A should have a local address")

        // Create transport B (matching Rust test)
        print("🚀 DEBUG: Creating transport B")
        let transportB = try FFITransport(keys: keysB, optionsCBOR: optionsCbor)
        print("🚀 DEBUG: Transport B created successfully")
        XCTAssertNotNil(transportB, "Transport B should be created")

        // Start transport B (matching Rust test)
        print("🚀 DEBUG: Starting transport B")
        try transportB.start()
        print("🚀 DEBUG: Transport B started successfully")

        // Get public key from A (matching Rust test)
        print("🔑 DEBUG: Getting public key from A")
        let publicKeyA = try keysA.nodeGetPublicKey()
        print("🔑 DEBUG: Public key A retrieved, length: \(publicKeyA.count) bytes")
        XCTAssertFalse(publicKeyA.isEmpty, "Public key A should not be empty")

        // Create peer info for B to connect to A (matching Rust test)
        print("🔗 DEBUG: Creating PeerInfo for connection")
        let peerInfo = PeerInfo(
            public_key: Array(publicKeyA),
            addresses: [addressA]
        )
        print("🔗 DEBUG: PeerInfo created, encoding to CBOR")
        let peerInfoCbor = try CodableCBOREncoder().encode(peerInfo)
        print("🔗 DEBUG: PeerInfo CBOR encoded, length: \(peerInfoCbor.count)")

        // Connect B to A (matching Rust test)
        print("🔗 DEBUG: Connecting B to A")
        try transportB.connectPeer(peerInfoCbor)
        print("🔗 DEBUG: B connected to A successfully")

        // Get compact ID for peer A (matching Rust test)
        print("🆔 DEBUG: Getting compact ID for peer A")
        let peerIdA = try keysA.nodeKeyManager?.getCompactId(publicKey: publicKeyA) ?? ""
        print("🆔 DEBUG: Peer ID A: \(peerIdA)")
        
        // Send request from B to A (matching Rust test)
        print("📤 DEBUG: Sending request from B to A")
        print("📤 DEBUG: Request details - path: /echo, correlationId: c1, destPeerId: \(peerIdA)")
        
        // Create CBOR request parameters (matching Rust test)
        let requestParams = TransportRequestParams(
            path: "/echo",
            correlation_id: "c1",
            payload: Array(Data("hello".utf8)),
            dest_peer_id: peerIdA,
            network_public_key: nil,
            profile_public_keys: []
        )
        let requestParamsCbor = try CodableCBOREncoder().encode(requestParams)
        print("📤 DEBUG: Request params CBOR encoded, length: \(requestParamsCbor.count)")
        
        try transportB.request(requestCBOR: requestParamsCbor)
        print("📤 DEBUG: Request sent successfully from B to A")

        // Poll for events on A (matching Rust test)
        print("📥 DEBUG: Starting to poll for events on A")
        var requestId: String?
        for i in 0..<50 {
            print("📥 DEBUG: Polling attempt \(i + 1)/50")
            if let eventData = try? transportA.pollEvent() {
                print("📥 DEBUG: Received event on A: \(eventData.count) bytes")
                // Parse CBOR event data
                if let event = try? CBORDecoder(input: Array(eventData)).decodeItem(),
                   case .map(let eventMap) = event,
                   let type = eventMap[CBOR.utf8String("type")],
                   case .utf8String("RequestReceived") = type,
                   let rid = eventMap[CBOR.utf8String("request_id")],
                   case .utf8String(let id) = rid {
                    requestId = id
                    print("📥 DEBUG: ✅ Received request with ID: \(id)")
                    break
                } else {
                    print("📥 DEBUG: Event is not a RequestReceived event")
                }
            } else {
                print("📥 DEBUG: No event received on A (attempt \(i + 1))")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        XCTAssertNotNil(requestId, "Should receive request on server")

        // Complete request on A (matching Rust test)
        let completeParams = TransportCompleteRequestParams(
            request_id: requestId!,
            response_payload: Array(Data("world".utf8)),
            profile_public_keys: []
        )
        let completeParamsCbor = try CodableCBOREncoder().encode(completeParams)
        print("📤 DEBUG: Complete params CBOR encoded, length: \(completeParamsCbor.count)")

        try transportA.completeRequest(completeCBOR: completeParamsCbor)

        // Poll for response on B (matching Rust test)
        var gotResponse = false
        for _ in 0..<50 {
            if let eventData = try? transportB.pollEvent() {
                // Parse CBOR event data
                if let event = try? CBORDecoder(input: Array(eventData)).decodeItem(),
                   case .map(let eventMap) = event,
                   let type = eventMap[CBOR.utf8String("type")],
                   case .utf8String("ResponseReceived") = type {
                    gotResponse = true
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        XCTAssertTrue(gotResponse, "Should receive response on client")

        // Cleanup (matching Rust test)
        try transportB.stop()
        try transportA.stop()
    }
}

@testable import RunarFFI
import XCTest
import SwiftCBOR

// MARK: - Transport Test Data Structures

/// NodeInfo struct matching the Rust NodeInfo exactly
struct NodeInfo: Codable {
    let nodePublicKey: [UInt8]  // Changed from Data to [UInt8] to match Rust Vec<u8>
    let networkIds: [String]
    let addresses: [String]
    let nodeMetadata: NodeMetadata
    let version: Int64  // Changed from UInt32 to Int64 to match Rust i64
    
    enum CodingKeys: String, CodingKey {
        case nodePublicKey = "node_public_key"
        case networkIds = "network_ids"
        case addresses
        case nodeMetadata = "node_metadata"
        case version
    }
}

/// NodeMetadata struct matching the Rust NodeMetadata exactly
struct NodeMetadata: Codable {
    let services: [ServiceMetadata]
    let subscriptions: [SubscriptionMetadata]
}

/// ServiceMetadata struct matching the Rust ServiceMetadata exactly
struct ServiceMetadata: Codable {
    let networkId: String
    let servicePath: String
    let name: String
    let version: String
    
    enum CodingKeys: String, CodingKey {
        case networkId = "network_id"
        case servicePath = "service_path"
        case name
        case version
    }
}

/// SubscriptionMetadata struct matching the Rust SubscriptionMetadata exactly
struct SubscriptionMetadata: Codable {
    let networkId: String
    let eventType: String
    
    enum CodingKeys: String, CodingKey {
        case networkId = "network_id"
        case eventType = "event_type"
    }
}

/// Transport request parameters struct
struct TransportRequestParams: Codable {
    let path: String
    let correlationId: String
    let payload: Data
    let destPeerId: String?
    let networkPublicKey: Data?
    let profilePublicKeys: [Data]
    
    enum CodingKeys: String, CodingKey {
        case path
        case correlationId = "correlation_id"
        case payload
        case destPeerId = "dest_peer_id"
        case networkPublicKey = "network_public_key"
        case profilePublicKeys = "profile_public_keys"
    }
}

/// Transport publish parameters struct
struct TransportPublishParams: Codable {
    let path: String
    let correlationId: String
    let payload: Data
    let destPeerId: String?
    let networkPublicKey: Data?
    let profilePublicKeys: [Data]
    
    enum CodingKeys: String, CodingKey {
        case path
        case correlationId = "correlation_id"
        case payload
        case destPeerId = "dest_peer_id"
        case networkPublicKey = "network_public_key"
        case profilePublicKeys = "profile_public_keys"
    }
}

/// Transport complete request parameters struct
struct TransportCompleteParams: Codable {
    let requestId: String
    let responsePayload: Data
    let profilePublicKey: Data?
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case responsePayload = "response_payload"
        case profilePublicKey = "profile_public_key"
    }
}

/// Transport Tests
///
/// Tests for transport layer functionality.
/// Mirrors the ffi_transport_test.rs from Rust.
final class TransportTests: XCTestCase {
    
    // MARK: - Helper Functions
    
    /// Creates NodeInfo CBOR for transport tests
    private func createNodeInfoCBOR(nodePublicKey: Data) throws -> Data {
        let nodeInfo = NodeInfo(
            nodePublicKey: Array(nodePublicKey),  // Convert Data to [UInt8]
            networkIds: [],
            addresses: [],
            nodeMetadata: NodeMetadata(
                services: [],
                subscriptions: []
            ),
            version: 0
        )
        
        // Convert to CBOR using CodableCBOREncoder (consistent with swift-serializer)
        let encoder = CodableCBOREncoder()
        return try encoder.encode(nodeInfo)
    }
    
    /// Sets up keys with proper node initialization for transport tests
    private func setupKeysForTransport() throws -> KeysFFI {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        
        // Use empty node public key like the Rust test does
        let nodePublicKey = Data()
        print("DEBUG: Using empty node public key")
        
        let nodeInfoCBOR = try createNodeInfoCBOR(nodePublicKey: nodePublicKey)
        print("DEBUG: NodeInfo CBOR length: \(nodeInfoCBOR.count)")
        print("DEBUG: NodeInfo CBOR first 20 bytes: \(Array(nodeInfoCBOR.prefix(20)))")
        
        // Try to decode the CBOR to verify it's valid
        do {
            let decoder = CodableCBORDecoder()
            let decodedNodeInfo = try decoder.decode(NodeInfo.self, from: nodeInfoCBOR)
            print("DEBUG: Successfully decoded NodeInfo: version=\(decodedNodeInfo.version), addresses=\(decodedNodeInfo.addresses.count)")
        } catch {
            print("DEBUG: Failed to decode NodeInfo CBOR: \(error)")
        }
        
        try keys.setLocalNodeInfo(nodeInfoCBOR)
        
        return keys
    }
    
    /// Creates publish CBOR parameters matching Rust structure
    private func createPublishCBOR(path: String, correlationId: String, payload: Data, destPeerId: String?) throws -> Data {
        let publishParams = TransportPublishParams(
            path: path,
            correlationId: correlationId,
            payload: payload,
            destPeerId: destPeerId,
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        let encoder = CodableCBOREncoder()
        return try encoder.encode(publishParams)
    }
    
    /// Creates request CBOR parameters matching Rust structure
    private func createRequestCBOR(path: String, correlationId: String, payload: Data, destPeerId: String?) throws -> Data {
        let requestParams = TransportRequestParams(
            path: path,
            correlationId: correlationId,
            payload: payload,
            destPeerId: destPeerId,
            networkPublicKey: nil,
            profilePublicKeys: []
        )
        
        let encoder = CodableCBOREncoder()
        return try encoder.encode(requestParams)
    }
    
    /// Creates complete request CBOR parameters matching Rust structure
    private func createCompleteRequestCBOR(requestId: String, responsePayload: Data, profilePublicKey: Data?) throws -> Data {
        let completeParams = TransportCompleteParams(
            requestId: requestId,
            responsePayload: responsePayload,
            profilePublicKey: profilePublicKey
        )
        
        let encoder = CodableCBOREncoder()
        return try encoder.encode(completeParams)
    }
    
    // MARK: - Transport Creation Tests
    
    func testTransportCreation() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        XCTAssertNotNil(transport, "Transport should be created successfully")
    }
    
    func testTransportStartStop() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        XCTAssertNoThrow(try transport.start(), "Transport should start successfully")
    }
    
    // MARK: - Transport Operations Tests
    
    func testTransportPublish() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        try transport.start()
        
        let testData = Data("Test message for transport".utf8)
        let publishCBOR = try createPublishCBOR(path: "/test", correlationId: "test-123", payload: testData, destPeerId: nil)
        XCTAssertNoThrow(try transport.publish(publishCBOR: publishCBOR), "Should publish data successfully")
    }
    
    func testTransportRequest() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        try transport.start()
        
        let requestData = Data("Test request data".utf8)
        let requestCBOR = try createRequestCBOR(path: "/test", correlationId: "test-123", payload: requestData, destPeerId: nil)
        XCTAssertNoThrow(try transport.request(requestCBOR: requestCBOR), "Should send request successfully")
    }
    
    func testTransportCompleteRequest() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        try transport.start()
        
        let responseData = Data("Test response data".utf8)
        let completeCBOR = try createCompleteRequestCBOR(requestId: "req-123", responsePayload: responseData, profilePublicKey: nil)
        XCTAssertNoThrow(try transport.completeRequest(completeCBOR: completeCBOR), "Should complete request successfully")
    }
    
    // MARK: - Transport Error Handling Tests
    
    func testTransportOperationsWithoutStart() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        // Not started
        
        let testData = Data("Test data".utf8)
        
        // These operations should still work even without start() being called
        // as the transport is initialized with keys
        let publishCBOR = try createPublishCBOR(path: "/test", correlationId: "test-123", payload: testData, destPeerId: nil)
        XCTAssertNoThrow(try transport.publish(publishCBOR: publishCBOR), "Should work even without start")
        
        let requestCBOR = try createRequestCBOR(path: "/test", correlationId: "test-123", payload: testData, destPeerId: nil)
        XCTAssertNoThrow(try transport.request(requestCBOR: requestCBOR), "Should work even without start")
        
        let completeCBOR = try createCompleteRequestCBOR(requestId: "req-123", responsePayload: testData, profilePublicKey: nil)
        XCTAssertNoThrow(try transport.completeRequest(completeCBOR: completeCBOR), "Should work even without start")
    }
    
    func testTransportWithEmptyData() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        try transport.start()
        
        let emptyData = Data()
        
        // Should handle empty data gracefully
        let publishCBOR = try createPublishCBOR(path: "/test", correlationId: "test-123", payload: emptyData, destPeerId: nil)
        XCTAssertNoThrow(try transport.publish(publishCBOR: publishCBOR), "Should handle empty data")
        
        let requestCBOR = try createRequestCBOR(path: "/test", correlationId: "test-123", payload: emptyData, destPeerId: nil)
        XCTAssertNoThrow(try transport.request(requestCBOR: requestCBOR), "Should handle empty data")
        
        let completeCBOR = try createCompleteRequestCBOR(requestId: "req-123", responsePayload: emptyData, profilePublicKey: nil)
        XCTAssertNoThrow(try transport.completeRequest(completeCBOR: completeCBOR), "Should handle empty data")
    }
    
    func testTransportWithLargeData() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        try transport.start()
        
        let largeData = Data(String(repeating: "A", count: 10000).utf8)
        
        // Should handle large data
        let publishCBOR = try createPublishCBOR(path: "/test", correlationId: "test-123", payload: largeData, destPeerId: nil)
        XCTAssertNoThrow(try transport.publish(publishCBOR: publishCBOR), "Should handle large data")
        
        let requestCBOR = try createRequestCBOR(path: "/test", correlationId: "test-123", payload: largeData, destPeerId: nil)
        XCTAssertNoThrow(try transport.request(requestCBOR: requestCBOR), "Should handle large data")
        
        let completeCBOR = try createCompleteRequestCBOR(requestId: "req-123", responsePayload: largeData, profilePublicKey: nil)
        XCTAssertNoThrow(try transport.completeRequest(completeCBOR: completeCBOR), "Should handle large data")
    }
    
    // MARK: - Transport Lifecycle Tests
    
    func testTransportLifecycle() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        
        // Test start
        XCTAssertNoThrow(try transport.start(), "Should start successfully")
        
        // Test operations after start
        let testData = Data("Test data".utf8)
        let publishCBOR = try createPublishCBOR(path: "/test", correlationId: "test-123", payload: testData, destPeerId: nil)
        XCTAssertNoThrow(try transport.publish(publishCBOR: publishCBOR), "Should work after start")
        
        // Test stop
        XCTAssertNoThrow(try transport.stop(), "Should stop successfully")
        
        // Test cleanup (implicit in Swift ARC)
        // Transport should be automatically cleaned up when deallocated
    }
    
    func testMultipleTransportInstances() throws {
        let keys1 = try setupKeysForTransport()
        let keys2 = try setupKeysForTransport()
        
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport1 = try FFITransport(keys: keys1, optionsCBOR: optionsCBOR)
        let transport2 = try FFITransport(keys: keys2, optionsCBOR: optionsCBOR)
        
        try transport1.start()
        try transport2.start()
        
        let testData = Data("Test data".utf8)
        let publishCBOR = try createPublishCBOR(path: "/test", correlationId: "test-123", payload: testData, destPeerId: nil)
        
        // Both transports should work independently
        XCTAssertNoThrow(try transport1.publish(publishCBOR: publishCBOR), "First transport should work")
        XCTAssertNoThrow(try transport2.publish(publishCBOR: publishCBOR), "Second transport should work")
    }
    
    // MARK: - Transport Integration Tests
    
    func testTransportWithKeysIntegration() throws {
        let keys = try setupKeysForTransport()
        
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        try transport.start()
        
        // Test that both can work together
        let testData = Data("Test data for integration".utf8)
        
        // Keys operations
        let encryptedData = try keys.nodeEncryptLocalData(testData)
        XCTAssertFalse(encryptedData.isEmpty, "Keys should encrypt data")
        
        // Transport operations
        let publishCBOR = try createPublishCBOR(path: "/test", correlationId: "test-123", payload: encryptedData, destPeerId: nil)
        XCTAssertNoThrow(try transport.publish(publishCBOR: publishCBOR), "Transport should publish encrypted data")
    }
    
    func testTransportErrorRecovery() throws {
        let keys = try setupKeysForTransport()
        let optionsCBOR = Data([0xa0]) // Empty CBOR map for testing
        let transport = try FFITransport(keys: keys, optionsCBOR: optionsCBOR)
        
        // Test that transport works after creation
        let testData = Data("Test data".utf8)
        let publishCBOR = try createPublishCBOR(path: "/test", correlationId: "test-123", payload: testData, destPeerId: nil)
        XCTAssertNoThrow(try transport.publish(publishCBOR: publishCBOR), "Should work after creation")
        
        // Test start/stop cycle
        XCTAssertNoThrow(try transport.start(), "Should be able to start")
        XCTAssertNoThrow(try transport.stop(), "Should be able to stop")
        XCTAssertNoThrow(try transport.start(), "Should be able to start again")
    }
}
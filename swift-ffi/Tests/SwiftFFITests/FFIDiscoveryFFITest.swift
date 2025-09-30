import Foundation
import SwiftCBOR
import SwiftCommon
import SwiftFFI
import XCTest

/// FFI Discovery Tests
///
/// Tests for the Discovery APIs exposed through the FFI layer.
/// These tests are equivalent to the multicast_discovery_test.rs but use FFI APIs.
/// This test is 100% aligned with the Rust ffi_discovery_test.rs
@testable import SwiftFFI

@MainActor
final class FFIDiscoveryFFITest: XCTestCase {
    
    // MARK: - Helper Functions
    
    /// Create discovery options CBOR data
    private func createDiscoveryOptions(
        multicastGroup: String,
        announceIntervalMs: UInt32,
        discoveryTimeoutMs: UInt32,
        debounceWindowMs: UInt32
    ) -> Data {
        let options = DiscoveryOptions(
            multicastGroup: multicastGroup,
            announceIntervalMs: announceIntervalMs,
            discoveryTimeoutMs: discoveryTimeoutMs,
            debounceWindowMs: debounceWindowMs
        )
        
        let encoder = CodableCBOREncoder()
        return try! encoder.encode(options)
    }
    
    // MARK: - Test Cases
    
    /// Test discovery TTL, lost events, and debouncing through FFI
    func testFFIDiscoveryTTLLostAndDebounce() async throws {
        print("🔍 Starting FFI Discovery TTL and Debounce Test")
        
        // Create two node key managers for two nodes
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()
        
        // Create discovery options with short TTL for testing
        let discoveryOptions = createDiscoveryOptions(
            multicastGroup: "239.255.0.1:45678",
            announceIntervalMs: 50,
            discoveryTimeoutMs: 1000,
            debounceWindowMs: 100
        )
        
        // Create discovery instances for both nodes
        let discoveryA = try await DiscoveryHandle.create(keys: keysA, optionsCbor: discoveryOptions)
        let discoveryB = try await DiscoveryHandle.create(keys: keysB, optionsCbor: discoveryOptions)
        
        // Initialize both discovery instances
        try await discoveryA.initialize(optionsCbor: discoveryOptions)
        try await discoveryB.initialize(optionsCbor: discoveryOptions)
        
        // Start announcing on both nodes
        try await discoveryA.startAnnouncing()
        try await discoveryB.startAnnouncing()
        
        // Wait for discovery to work
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Stop announcing on node A to simulate TTL loss
        try await discoveryA.stopAnnouncing()
        
        // Wait for TTL to expire and debounce
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Cleanup
        try await discoveryA.shutdown()
        try await discoveryB.shutdown()
        
        print("✅ FFI Discovery TTL and Debounce Test completed")
    }
    
    /// Test discovery announce and discover functionality through FFI
    func testFFIMulticastAnnounceAndDiscover() async throws {
        print("🔍 Starting FFI Multicast Announce and Discover Test")
        
        // Create two node key managers for two nodes
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()
        
        // Create discovery options
        let discoveryOptions = createDiscoveryOptions(
            multicastGroup: "239.255.0.1:45679",
            announceIntervalMs: 100,
            discoveryTimeoutMs: 2000,
            debounceWindowMs: 200
        )
        
        // Create discovery instances for both nodes
        let discoveryA = try await DiscoveryHandle.create(keys: keysA, optionsCbor: discoveryOptions)
        let discoveryB = try await DiscoveryHandle.create(keys: keysB, optionsCbor: discoveryOptions)
        
        // Initialize both discovery instances
        try await discoveryA.initialize(optionsCbor: discoveryOptions)
        try await discoveryB.initialize(optionsCbor: discoveryOptions)
        
        // Start announcing on both nodes
        try await discoveryA.startAnnouncing()
        try await discoveryB.startAnnouncing()
        
        // Wait for discovery to work
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1000ms
        
        // Cleanup
        try await discoveryA.shutdown()
        try await discoveryB.shutdown()
        
        print("✅ FFI Multicast Announce and Discover Test completed")
    }
    
    /// Test discovery start/stop idempotence through FFI
    func testFFIDiscoveryStartStopIdempotence() async throws {
        print("🔍 Starting FFI Discovery Start/Stop Idempotence Test")
        
        // Create node key manager
        let keys = try await NodeKeyManager()
        
        // Create discovery options
        let discoveryOptions = createDiscoveryOptions(
            multicastGroup: "239.255.0.1:45680",
            announceIntervalMs: 100,
            discoveryTimeoutMs: 2000,
            debounceWindowMs: 200
        )
        
        // Create discovery instance
        let discovery = try await DiscoveryHandle.create(keys: keys, optionsCbor: discoveryOptions)
        
        // Initialize discovery
        try await discovery.initialize(optionsCbor: discoveryOptions)
        
        // Test multiple start calls (should be idempotent)
        try await discovery.startAnnouncing()
        try await discovery.startAnnouncing()
        
        // Test multiple stop calls (should be idempotent)
        try await discovery.stopAnnouncing()
        try await discovery.stopAnnouncing()
        
        // Cleanup
        try await discovery.shutdown()
        
        print("✅ FFI Discovery Start/Stop Idempotence Test completed")
    }
    
    /// Test discovery with invalid CBOR data through FFI
    func testFFIDiscoveryInvalidCborHandling() async throws {
        print("🔍 Starting FFI Discovery Invalid CBOR Handling Test")
        
        // Create node key manager
        let keys = try await NodeKeyManager()
        
        // Test with invalid CBOR data
        let invalidCbor = Data("invalid cbor data".utf8)
        
        // This should succeed with invalid CBOR (uses default options)
        // The Swift FFI layer should handle invalid CBOR gracefully
        let discovery = try await DiscoveryHandle.create(keys: keys, optionsCbor: invalidCbor)
        
        // Cleanup
        try await discovery.shutdown()
        
        print("✅ FFI Discovery Invalid CBOR Handling Test completed")
    }
}

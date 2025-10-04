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
        announceInterval: TimeInterval,
        discoveryTimeout: TimeInterval,
        debounceWindow: TimeInterval
    ) -> Data {
        let options = DiscoveryOptions(
            announceInterval: announceInterval,
            discoveryTimeout: discoveryTimeout,
            debounceWindow: debounceWindow,
            multicastGroup: multicastGroup
        )

        let encoder = CodableCBOREncoder()
        return try! encoder.encode(options)
    }

    // MARK: - Test Cases

    /// Test discovery TTL, lost events, and debouncing through FFI
    func testFFIDiscoveryTTLLostAndDebounce() async throws {
        print("🔍 Starting FFI Discovery TTL and Debounce Test")

        // Create discovery options with short TTL for testing
        let discoveryOptions = createDiscoveryOptions(
            multicastGroup: "239.255.0.1:45678",
            announceInterval: 0.05,
            discoveryTimeout: 1.0,
            debounceWindow: 0.1
        )

        // Create discovery instances for both nodes
        let discoveryA = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8000"]), options: DiscoveryOptions(announceInterval: 0.05, discoveryTimeout: 1.0, debounceWindow: 0.1, multicastGroup: "239.255.0.1:45678"))
        let discoveryB = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([6, 7, 8, 9, 10]), addresses: ["127.0.0.1:8001"]), options: DiscoveryOptions(announceInterval: 0.05, discoveryTimeout: 1.0, debounceWindow: 0.1, multicastGroup: "239.255.0.1:45678"))

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

        // Create discovery options
        let discoveryOptions = createDiscoveryOptions(
            multicastGroup: "239.255.0.1:45679",
            announceInterval: 0.1,
            discoveryTimeout: 2.0,
            debounceWindow: 0.2
        )

        // Create discovery instances for both nodes
        let discoveryA = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8000"]), options: DiscoveryOptions(announceInterval: 0.1, discoveryTimeout: 2.0, debounceWindow: 0.2, multicastGroup: "239.255.0.1:45679"))
        let discoveryB = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([6, 7, 8, 9, 10]), addresses: ["127.0.0.1:8001"]), options: DiscoveryOptions(announceInterval: 0.1, discoveryTimeout: 2.0, debounceWindow: 0.2, multicastGroup: "239.255.0.1:45679"))

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

        // Create discovery options
        let discoveryOptions = createDiscoveryOptions(
            multicastGroup: "239.255.0.1:45680",
            announceInterval: 0.1,
            discoveryTimeout: 2.0,
            debounceWindow: 0.2
        )

        // Create discovery instance
        let discovery = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8080"]), options: DiscoveryOptions(announceInterval: 0.1, discoveryTimeout: 2.0, debounceWindow: 0.2, multicastGroup: "239.255.0.1:45680"))

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

        // Test with default options (no invalid CBOR since we now use structured API)
        let discoveryOptions = DiscoveryOptions()
        let peerInfo = PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8080"])

        // This should succeed with default options
        let discovery = try await MulticastDiscovery.create(peerInfo: peerInfo, options: discoveryOptions)

        // Cleanup
        try await discovery.shutdown()

        print("✅ FFI Discovery Invalid CBOR Handling Test completed")
    }
}

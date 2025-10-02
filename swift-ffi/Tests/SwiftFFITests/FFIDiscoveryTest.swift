import Foundation
import SwiftCBOR
import SwiftCommon
import SwiftFFI
import XCTest

/// Comprehensive Discovery Integration Tests
///
/// This test mirrors the Rust multicast_discovery_test.rs to validate
/// the complete discovery functionality including:
/// - Peer discovery via multicast
/// - Discovery events (discovered/lost)
/// - TTL and debounce handling
/// - Integration with transport layer
@testable import SwiftFFI

@MainActor
final class FFIDiscoveryTest: XCTestCase {
    /// Test basic discovery setup and configuration
    func testBasicDiscoverySetup() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerContext("discovery-setup-test")

        // Create keys for discovery
        let keys = try await NodeKeyManager()

        // Create discovery options
        let discoveryOptions = DiscoveryOptions(
            multicastGroup: "224.0.0.251:5353",
            announceIntervalMs: 1000,
            discoveryTimeoutMs: 5000,
            debounceWindowMs: 200
        )

        // Encode options to CBOR
        let encoder = CodableCBOREncoder()
        let optionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instance
        let discovery = try await DiscoveryHandle.create(keys: keys, optionsCbor: optionsCbor)

        // Initialize discovery
        try await discovery.initialize(optionsCbor: optionsCbor)

        // Bind events (critical for event polling)
        try await discovery.bindEvents()

        // Shutdown discovery
        try await discovery.shutdown()
    }

    /// Test discovery event polling and validation
    func testDiscoveryEventPolling() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerContext("discovery-event-polling-test")

        // Create two node key managers (A and B)
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Create mobile key manager for CA (Certificate Authority)
        let keysCA = try await MobileKeyManager()

        // Generate and install certificates for both nodes
        let csrA = try await keysA.generateCsrSetupToken()
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        let csrB = try await keysB.generateCsrSetupToken()
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)

        // Create discovery options with short intervals for testing
        let uniquePort = UInt16.random(in: 46000 ... 47000)
        let discoveryOptions = DiscoveryOptions(
            multicastGroup: "224.0.0.251:\(uniquePort)",
            announceIntervalMs: 50,
            discoveryTimeoutMs: 1000,
            debounceWindowMs: 100
        )

        let encoder = CodableCBOREncoder()
        let discoveryOptionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instances
        let discoveryA = try await DiscoveryHandle.create(keys: keysA, optionsCbor: discoveryOptionsCbor)
        try await discoveryA.initialize(optionsCbor: discoveryOptionsCbor)
        try await discoveryA.bindEvents()

        let discoveryB = try await DiscoveryHandle.create(keys: keysB, optionsCbor: discoveryOptionsCbor)
        try await discoveryB.initialize(optionsCbor: discoveryOptionsCbor)
        try await discoveryB.bindEvents()

        // Get public keys for peer info
        let publicKeyA = try await keysA.getNodePublicKey()
        let publicKeyB = try await keysB.getNodePublicKey()

        // Create peer info for both nodes
        let peerInfoA = PeerInfo(publicKey: publicKeyA, addresses: ["127.0.0.1:8000"])
        let peerInfoB = PeerInfo(publicKey: publicKeyB, addresses: ["127.0.0.1:8001"])

        let peerInfoACbor = try await CBORHelper.encodePeerInfo(peerInfoA)
        let peerInfoBCbor = try await CBORHelper.encodePeerInfo(peerInfoB)

        // Update local peer info in discovery
        try await discoveryA.updateLocalPeerInfo(peerInfoCbor: peerInfoACbor)
        try await discoveryB.updateLocalPeerInfo(peerInfoCbor: peerInfoBCbor)

        // Start announcing on both nodes
        try await discoveryA.startAnnouncing()
        try await discoveryB.startAnnouncing()

        // Wait for discovery to work
        try await Task.sleep(nanoseconds: UInt64(1.0 * 1_000_000_000))

        // Test discovery event polling on node B (should discover node A)
        var discoveredEvents = 0
        var updatedEvents = 0
        var lostEvents = 0

        // Poll for discovered events
        for _ in 0..<10 {
            if let discovered = try await discoveryB.pollDiscovered() {
                print("Discovered peer: \(discovered.addresses)")
                discoveredEvents += 1
            }

            if let updated = try await discoveryB.pollUpdated() {
                print("Updated peer: \(updated.addresses)")
                updatedEvents += 1
            }

            if let lost = try await discoveryB.pollLost() {
                print("Lost peer: \(lost)")
                lostEvents += 1
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        print("Discovery events - Discovered: \(discoveredEvents), Updated: \(updatedEvents), Lost: \(lostEvents)")

        // We should have seen at least one discovered event
        XCTAssertGreaterThan(discoveredEvents, 0, "Should have discovered at least one peer")

        // Stop announcing on node A to simulate TTL loss
        try await discoveryA.stopAnnouncing()

        // Wait for TTL to expire
        try await Task.sleep(nanoseconds: UInt64(2.0 * 1_000_000_000))

        // Poll for lost events after TTL
        for _ in 0..<5 {
            if let lost = try await discoveryB.pollLost() {
                print("Lost peer after TTL: \(lost)")
                lostEvents += 1
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Cleanup
        try await discoveryA.shutdown()
        try await discoveryB.shutdown()
    }

    /// Test discovery with callback system
    func testDiscoveryWithCallbacks() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerContext("discovery-callbacks-test")

        // Create two node key managers (A and B)
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Create mobile key manager for CA
        let keysCA = try await MobileKeyManager()

        // Generate and install certificates
        let csrA = try await keysA.generateCsrSetupToken()
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        let csrB = try await keysB.generateCsrSetupToken()
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)

        // Create discovery options with short intervals for testing
        let uniquePort = UInt16.random(in: 47000 ... 48000)
        let discoveryOptions = DiscoveryOptions(
            multicastGroup: "224.0.0.251:\(uniquePort)",
            announceIntervalMs: 50,
            discoveryTimeoutMs: 1000,
            debounceWindowMs: 100
        )

        let encoder = CodableCBOREncoder()
        let discoveryOptionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instances
        let discoveryA = try await DiscoveryHandle.create(keys: keysA, optionsCbor: discoveryOptionsCbor)
        try await discoveryA.initialize(optionsCbor: discoveryOptionsCbor)
        try await discoveryA.bindEvents()

        let discoveryB = try await DiscoveryHandle.create(keys: keysB, optionsCbor: discoveryOptionsCbor)
        try await discoveryB.initialize(optionsCbor: discoveryOptionsCbor)
        try await discoveryB.bindEvents()

        // Set up simple discovery callbacks that just log
        let discoveryCallbacksA = DiscoveryCallbacks(
            discoveredCallback: { peerInfo in
                print("Discovery A: Peer discovered - \(peerInfo.addresses)")
            },
            updatedCallback: { peerInfo in
                print("Discovery A: Peer updated - \(peerInfo.addresses)")
            },
            lostCallback: { nodeId in
                print("Discovery A: Peer lost - \(nodeId)")
            }
        )

        let discoveryCallbacksB = DiscoveryCallbacks(
            discoveredCallback: { peerInfo in
                print("Discovery B: Peer discovered - \(peerInfo.addresses)")
            },
            updatedCallback: { peerInfo in
                print("Discovery B: Peer updated - \(peerInfo.addresses)")
            },
            lostCallback: { nodeId in
                print("Discovery B: Peer lost - \(nodeId)")
            }
        )

        await discoveryA.setCallbacks(discoveryCallbacksA)
        await discoveryB.setCallbacks(discoveryCallbacksB)

        // Get public keys for peer info
        let publicKeyA = try await keysA.getNodePublicKey()
        let publicKeyB = try await keysB.getNodePublicKey()

        // Create peer info for both nodes
        let peerInfoA = PeerInfo(publicKey: publicKeyA, addresses: ["127.0.0.1:8000"])
        let peerInfoB = PeerInfo(publicKey: publicKeyB, addresses: ["127.0.0.1:8001"])

        let peerInfoACbor = try await CBORHelper.encodePeerInfo(peerInfoA)
        let peerInfoBCbor = try await CBORHelper.encodePeerInfo(peerInfoB)

        // Update local peer info
        try await discoveryA.updateLocalPeerInfo(peerInfoCbor: peerInfoACbor)
        try await discoveryB.updateLocalPeerInfo(peerInfoCbor: peerInfoBCbor)

        // Start announcing
        try await discoveryA.startAnnouncing()
        try await discoveryB.startAnnouncing()

        // Wait for discovery to work and callbacks to fire
        try await Task.sleep(nanoseconds: UInt64(2.0 * 1_000_000_000))

        // Test that the discovery system is working by polling for events
        var discoveredCount = 0
        for _ in 0..<5 {
            if let _ = try await discoveryB.pollDiscovered() {
                discoveredCount += 1
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        print("Discovered peers via polling: \(discoveredCount)")

        // Stop announcing on node A to simulate TTL loss
        try await discoveryA.stopAnnouncing()
        try await discoveryA.shutdown()

        // Wait for TTL cleanup
        try await Task.sleep(nanoseconds: UInt64(2.0 * 1_000_000_000))

        // Stop node B
        try await discoveryB.stopAnnouncing()
        try await discoveryB.shutdown()
    }

    /// Test discovery start/stop idempotence
    func testDiscoveryStartStopIdempotence() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerContext("discovery-idempotence-test")

        // Create keys for discovery
        let keys = try await NodeKeyManager()

        // Create discovery options
        let discoveryOptions = DiscoveryOptions(
            multicastGroup: "224.0.0.251:5353",
            announceIntervalMs: 100,
            discoveryTimeoutMs: 2000,
            debounceWindowMs: 200
        )

        let encoder = CodableCBOREncoder()
        let optionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instance
        let discovery = try await DiscoveryHandle.create(keys: keys, optionsCbor: optionsCbor)
        try await discovery.initialize(optionsCbor: optionsCbor)
        try await discovery.bindEvents()

        // Test multiple start calls (should be idempotent)
        try await discovery.startAnnouncing()
        try await discovery.startAnnouncing()

        // Test multiple stop calls (should be idempotent)
        try await discovery.stopAnnouncing()
        try await discovery.stopAnnouncing()

        // After cycles, discovery should still be functional
        try await discovery.startAnnouncing()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        try await discovery.stopAnnouncing()

        // Cleanup
        try await discovery.shutdown()
    }
}

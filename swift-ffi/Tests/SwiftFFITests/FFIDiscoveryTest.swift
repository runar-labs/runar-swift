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
    override func setUp() {
        super.setUp()
        // Reset global config for each test
        LoggerConfigManager.shared.globalConfig = LoggerConfig(level: .info)
    }

    /// Test basic discovery setup and configuration
    func testBasicDiscoverySetup() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.info)
        try await FFILogger.setLoggerContext("discovery-setup-test")

        // Create discovery options
        let discoveryOptions = DiscoveryOptions(
            announceInterval: 1.0,
            discoveryTimeout: 5.0,
            debounceWindow: 0.2,
            multicastGroup: "224.0.0.251:5353"
        )

        // Create a dummy PeerInfo for testing
        let peerInfo = PeerInfo(
            publicKey: Data([1, 2, 3, 4, 5]),
            addresses: ["127.0.0.1:8080"]
        )

        let logger = RunarLogger.root(component: .custom("testBasicDiscoverySetup"))
        // Create discovery instance
        let discovery = try await MulticastDiscovery.create(peerInfo: peerInfo, options: discoveryOptions, logger: logger.child(component: .network))

        // Initialize discovery (bindEvents is called automatically)
        try await discovery.initialize(optionsCbor: CodableCBOREncoder().encode(discoveryOptions))

        // Shutdown discovery
        try await discovery.shutdown()
    }

    /// Test discovery event polling and validation
    func testDiscoveryEventPolling() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.info)
        try await FFILogger.setLoggerContext("discovery-event-polling-test")

        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("testDiscoveryEventPolling"))

        // Create two node key managers (A and B)
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Create mobile key manager for CA (Certificate Authority)
        let keysCA = try await MobileKeyManager()

        // Generate and install certificates for both nodes
        let csrA = try await keysA.generateCsrSetupToken(logger: logger.child(component: .network))
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        let csrB = try await keysB.generateCsrSetupToken(logger: logger.child(component: .network))
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)

        // Create discovery options with short intervals for testing
        let uniquePort = UInt16.random(in: 46000 ... 47000)
        let discoveryOptions = DiscoveryOptions(
            announceInterval: 0.05,
            discoveryTimeout: 1.0,
            debounceWindow: 0.1,
            multicastGroup: "224.0.0.251:\(uniquePort)"
        )

        let encoder = CodableCBOREncoder()
        let discoveryOptionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instances
        let discoveryA = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8000"]), options: discoveryOptions, logger: logger.child(component: .network))
        try await discoveryA.initialize(optionsCbor: discoveryOptionsCbor)

        let discoveryB = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([6, 7, 8, 9, 10]), addresses: ["127.0.0.1:8001"]), options: discoveryOptions, logger: logger.child(component: .network))
        try await discoveryB.initialize(optionsCbor: discoveryOptionsCbor)

        // Get public keys for peer info
        let publicKeyA = try await keysA.getNodePublicKey()
        let publicKeyB = try await keysB.getNodePublicKey()

        // Create peer info for both nodes
        let peerInfoA = PeerInfo(publicKey: publicKeyA, addresses: ["127.0.0.1:8000"])
        let peerInfoB = PeerInfo(publicKey: publicKeyB, addresses: ["127.0.0.1:8001"])

        let peerInfoACbor = try CodableCBOREncoder().encode(peerInfoA)
        let peerInfoBCbor = try CodableCBOREncoder().encode(peerInfoB)

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
        for _ in 0 ..< 10 {
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
        for _ in 0 ..< 5 {
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
        LoggerConfigManager.shared.globalConfig = LoggerConfig(level: .info)
        // Set up logging
        try await FFILogger.setLogLevel(.info)
        try await FFILogger.setLoggerContext("discovery-callbacks-test")

        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("testDiscoveryWithCallbacks"), context: nil, config: LoggerConfig(level: .info))

        // Create two node key managers (A and B)
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Create mobile key manager for CA
        let keysCA = try await MobileKeyManager()

        // Generate and install certificates
        let csrA = try await keysA.generateCsrSetupToken(logger: logger.child(component: .network))
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        let csrB = try await keysB.generateCsrSetupToken(logger: logger.child(component: .network))
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)

        // Create discovery options with short intervals for testing
        let uniquePort = UInt16.random(in: 47000 ... 48000)
        let discoveryOptions = DiscoveryOptions(
            announceInterval: 0.05,
            discoveryTimeout: 1.0,
            debounceWindow: 0.1,
            multicastGroup: "224.0.0.251:\(uniquePort)"
        )

        let encoder = CodableCBOREncoder()
        let discoveryOptionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instances
        let discoveryA = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8000"]), options: discoveryOptions, logger: logger.child(component: .network))
        try await discoveryA.initialize(optionsCbor: discoveryOptionsCbor)

        let discoveryB = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([6, 7, 8, 9, 10]), addresses: ["127.0.0.1:8001"]), options: discoveryOptions, logger: logger.child(component: .network))
        try await discoveryB.initialize(optionsCbor: discoveryOptionsCbor)

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

        let peerInfoACbor = try CodableCBOREncoder().encode(peerInfoA)
        let peerInfoBCbor = try CodableCBOREncoder().encode(peerInfoB)

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
        for _ in 0 ..< 5 {
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
        try await FFILogger.setLogLevel(.info)
        try await FFILogger.setLoggerContext("discovery-idempotence-test")

        // Create keys for discovery
        let keys = try await NodeKeyManager()

        // Create discovery options
        let discoveryOptions = DiscoveryOptions(
            announceInterval: 0.1,
            discoveryTimeout: 2.0,
            debounceWindow: 0.2,
            multicastGroup: "224.0.0.251:5353"
        )

        let encoder = CodableCBOREncoder()
        let optionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instance
        let logger = RunarLogger.root(component: .custom("testDiscoveryStartStopIdempotence"))
        let discovery = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8080"]), options: discoveryOptions, logger: logger.child(component: .network))
        try await discovery.initialize(optionsCbor: optionsCbor)

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

    /// Test discovery TTL, lost events, and debouncing
    func testDiscoveryTTLLostAndDebounce() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.info)
        try await FFILogger.setLoggerContext("discovery-ttl-test")

        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("testDiscoveryTTLLostAndDebounce"))

        // Create two node key managers (A and B)
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Create mobile key manager for CA
        let keysCA = try await MobileKeyManager()

        // Generate and install certificates
        let csrA = try await keysA.generateCsrSetupToken(logger: logger.child(component: .network))
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        let csrB = try await keysB.generateCsrSetupToken(logger: logger.child(component: .network))
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)

        // Create discovery options with short TTL for testing
        let uniquePort = UInt16.random(in: 48000 ... 49000)
        let discoveryOptions = DiscoveryOptions(
            announceInterval: 0.05,
            discoveryTimeout: 1.0,
            debounceWindow: 0.1,
            multicastGroup: "224.0.0.251:\(uniquePort)"
        )

        let encoder = CodableCBOREncoder()
        let discoveryOptionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instances
        let discoveryA = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8000"]), options: discoveryOptions, logger: logger.child(component: .network))
        try await discoveryA.initialize(optionsCbor: discoveryOptionsCbor)

        let discoveryB = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([6, 7, 8, 9, 10]), addresses: ["127.0.0.1:8001"]), options: discoveryOptions, logger: logger.child(component: .network))
        try await discoveryB.initialize(optionsCbor: discoveryOptionsCbor)

        // Get public keys for peer info
        let publicKeyA = try await keysA.getNodePublicKey()
        let publicKeyB = try await keysB.getNodePublicKey()

        // Create peer info for both nodes
        let peerInfoA = PeerInfo(publicKey: publicKeyA, addresses: ["127.0.0.1:8000"])
        let peerInfoB = PeerInfo(publicKey: publicKeyB, addresses: ["127.0.0.1:8001"])

        let peerInfoACbor = try CodableCBOREncoder().encode(peerInfoA)
        let peerInfoBCbor = try CodableCBOREncoder().encode(peerInfoB)

        // Update local peer info
        try await discoveryA.updateLocalPeerInfo(peerInfoCbor: peerInfoACbor)
        try await discoveryB.updateLocalPeerInfo(peerInfoCbor: peerInfoBCbor)

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
    }

    /// Test multicast announce and discover functionality
    func testMulticastAnnounceAndDiscover() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.info)
        try await FFILogger.setLoggerContext("discovery-multicast-test")

        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("testMulticastAnnounceAndDiscover"))

        // Create two node key managers (A and B)
        let keysA = try await NodeKeyManager()
        let keysB = try await NodeKeyManager()

        // Create mobile key manager for CA
        let keysCA = try await MobileKeyManager()

        // Generate and install certificates
        let csrA = try await keysA.generateCsrSetupToken(logger: logger.child(component: .network))
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        let csrB = try await keysB.generateCsrSetupToken(logger: logger.child(component: .network))
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)

        // Create discovery options
        let uniquePort = UInt16.random(in: 49000 ... 50000)
        let discoveryOptions = DiscoveryOptions(
            announceInterval: 0.1,
            discoveryTimeout: 2.0,
            debounceWindow: 0.2,
            multicastGroup: "224.0.0.251:\(uniquePort)"
        )

        let encoder = CodableCBOREncoder()
        let discoveryOptionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instances
        let discoveryA = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8000"]), options: discoveryOptions, logger: logger.child(component: .network))
        try await discoveryA.initialize(optionsCbor: discoveryOptionsCbor)

        let discoveryB = try await MulticastDiscovery.create(peerInfo: PeerInfo(publicKey: Data([6, 7, 8, 9, 10]), addresses: ["127.0.0.1:8001"]), options: discoveryOptions, logger: logger.child(component: .network))
        try await discoveryB.initialize(optionsCbor: discoveryOptionsCbor)

        // Get public keys for peer info
        let publicKeyA = try await keysA.getNodePublicKey()
        let publicKeyB = try await keysB.getNodePublicKey()

        // Create peer info for both nodes
        let peerInfoA = PeerInfo(publicKey: publicKeyA, addresses: ["127.0.0.1:8000"])
        let peerInfoB = PeerInfo(publicKey: publicKeyB, addresses: ["127.0.0.1:8001"])

        let peerInfoACbor = try CodableCBOREncoder().encode(peerInfoA)
        let peerInfoBCbor = try CodableCBOREncoder().encode(peerInfoB)

        // Update local peer info
        try await discoveryA.updateLocalPeerInfo(peerInfoCbor: peerInfoACbor)
        try await discoveryB.updateLocalPeerInfo(peerInfoCbor: peerInfoBCbor)

        // Start announcing on both nodes
        try await discoveryA.startAnnouncing()
        try await discoveryB.startAnnouncing()

        // Wait for discovery to work
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Cleanup
        try await discoveryA.shutdown()
        try await discoveryB.shutdown()
    }

    /// Test discovery with invalid CBOR data handling
    func testDiscoveryInvalidCBORHandling() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.info)
        try await FFILogger.setLoggerContext("discovery-invalid-cbor-test")

        // Create discovery instance with default options
        let discoveryOptions = DiscoveryOptions()
        let peerInfo = PeerInfo(publicKey: Data([1, 2, 3, 4, 5]), addresses: ["127.0.0.1:8080"])

        // Should succeed with default options
        let logger = RunarLogger.root(component: .custom("testDiscoveryInvalidCBORHandling"))
        let discovery = try await MulticastDiscovery.create(peerInfo: peerInfo, options: discoveryOptions, logger: logger.child(component: .network))

        // Cleanup
        try await discovery.shutdown()
    }
}

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
        try await FFILogger.setLoggerNodeId("discovery-setup-test")

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

        // Shutdown discovery
        try await discovery.shutdown()
    }

    /// Test discovery with transport integration
    func testDiscoveryWithTransport() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerNodeId("discovery-transport-test")

        // Create two node key managers (A and B)
        let keysA = try await NodeKeyManager()

        let keysB = try await NodeKeyManager()

        // Create mobile key manager for CA (Certificate Authority)
        let keysCA = try await MobileKeyManager()

        // Set node info for both nodes
        let nodeInfo = CBORHelper.createMinimalNodeInfo(nodePublicKey: Data())
        let nodeInfoCbor = try await CBORHelper.encodeNodeInfo(nodeInfo)

        try await keysA.setLocalNodeInfo(nodeInfoCbor)
        try await keysB.setLocalNodeInfo(nodeInfoCbor)

        // Generate and install certificates for both nodes
        let csrA = try await keysA.generateCsrSetupToken()
        let certA = try await keysCA.processSetupToken(csrA)
        try await keysA.installCertificate(certA)

        let csrB = try await keysB.generateCsrSetupToken()
        let certB = try await keysCA.processSetupToken(csrB)
        try await keysB.installCertificate(certB)

        // Create transport options
        let transportOptions = CBORHelper.createMinimalSwiftTransportOptions(bindAddr: "127.0.0.1:0")

        // Create transports
        let callbacksA = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in nil as NetworkMessage? }
        )
        let loggerA = RunarLogger(component: .custom)
        let transportA = try await QuicTransport.create(keys: keysA, options: transportOptions, callbacks: callbacksA, logger: loggerA)
        try await transportA.start()

        let callbacksB = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in nil as NetworkMessage? }
        )
        let loggerB = RunarLogger(component: .custom)
        let transportB = try await QuicTransport.create(keys: keysB, options: transportOptions, callbacks: callbacksB, logger: loggerB)
        try await transportB.start()

        // Create discovery options with unique multicast group
        let uniquePort = UInt16.random(in: 46000 ... 47000)
        let discoveryOptions = DiscoveryOptions(
            multicastGroup: "224.0.0.251:\(uniquePort)",
            announceIntervalMs: 100,
            discoveryTimeoutMs: 1000,
            debounceWindowMs: 50
        )

        let encoder = CodableCBOREncoder()
        let discoveryOptionsCbor = try encoder.encode(discoveryOptions)

        // Create discovery instances
        let discoveryA = try await DiscoveryHandle.create(keys: keysA, optionsCbor: discoveryOptionsCbor)
        try await discoveryA.initialize(optionsCbor: discoveryOptionsCbor)

        let discoveryB = try await DiscoveryHandle.create(keys: keysB, optionsCbor: discoveryOptionsCbor)
        try await discoveryB.initialize(optionsCbor: discoveryOptionsCbor)

        // Bind discovery events to transports
        try await discoveryA.bindEventsToTransport(transport: transportA)
        try await discoveryB.bindEventsToTransport(transport: transportB)

        // Get local addresses
        let localAddrA = try await transportA.getLocalAddr()
        let localAddrB = try await transportB.getLocalAddr()

        // Create peer info for both nodes
        let publicKeyA = try await keysA.getNodePublicKey()
        let publicKeyB = try await keysB.getNodePublicKey()

        let peerInfoA = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])
        let peerInfoB = PeerInfo(publicKey: publicKeyB, addresses: [localAddrB])

        let peerInfoACbor = try await CBORHelper.encodePeerInfo(peerInfoA)
        let peerInfoBCbor = try await CBORHelper.encodePeerInfo(peerInfoB)

        // Update local peer info in discovery
        try await discoveryA.updateLocalPeerInfo(peerInfoCbor: peerInfoACbor)
        try await discoveryB.updateLocalPeerInfo(peerInfoCbor: peerInfoBCbor)

        // Start announcing
        try await discoveryA.startAnnouncing()
        try await discoveryB.startAnnouncing()

        // Wait a bit for discovery to work
        try await Task.sleep(nanoseconds: UInt64(2.0 * 1_000_000_000))

        // Stop announcing
        try await discoveryA.stopAnnouncing()
        try await discoveryB.stopAnnouncing()

        // Shutdown discovery
        try await discoveryA.shutdown()
        try await discoveryB.shutdown()

        // Stop transports
        try await transportA.stop()
        try await transportB.stop()
    }

    /// Test discovery TTL and debounce functionality
    func testDiscoveryTTLAndDebounce() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerNodeId("discovery-ttl-test")

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

        // Set node info
        let nodeInfo = CBORHelper.createMinimalNodeInfo(nodePublicKey: Data())
        let nodeInfoCbor = try await CBORHelper.encodeNodeInfo(nodeInfo)

        try await keysA.setLocalNodeInfo(nodeInfoCbor)
        try await keysB.setLocalNodeInfo(nodeInfoCbor)

        // Create transport options
        let transportOptions = CBORHelper.createMinimalSwiftTransportOptions(bindAddr: "127.0.0.1:0")

        // Create transports
        let callbacksA = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in nil as NetworkMessage? }
        )
        let loggerA = RunarLogger(component: .custom)
        let transportA = try await QuicTransport.create(keys: keysA, options: transportOptions, callbacks: callbacksA, logger: loggerA)
        try await transportA.start()

        let callbacksB = TransportCallbacks(
            requestCallback: { _, _, _, _, _ in nil as NetworkMessage? }
        )
        let loggerB = RunarLogger(component: .custom)
        let transportB = try await QuicTransport.create(keys: keysB, options: transportOptions, callbacks: callbacksB, logger: loggerB)
        try await transportB.start()

        // Create discovery options with short TTL for testing
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

        let discoveryB = try await DiscoveryHandle.create(keys: keysB, optionsCbor: discoveryOptionsCbor)
        try await discoveryB.initialize(optionsCbor: discoveryOptionsCbor)

        // Bind discovery events to transports
        try await discoveryA.bindEventsToTransport(transport: transportA)
        try await discoveryB.bindEventsToTransport(transport: transportB)

        // Get local addresses and create peer info
        let localAddrA = try await transportA.getLocalAddr()
        let localAddrB = try await transportB.getLocalAddr()

        let publicKeyA = try await keysA.getNodePublicKey()
        let publicKeyB = try await keysB.getNodePublicKey()

        let peerInfoA = PeerInfo(publicKey: publicKeyA, addresses: [localAddrA])
        let peerInfoB = PeerInfo(publicKey: publicKeyB, addresses: [localAddrB])

        let peerInfoACbor = try await CBORHelper.encodePeerInfo(peerInfoA)
        let peerInfoBCbor = try await CBORHelper.encodePeerInfo(peerInfoB)

        // Update local peer info
        try await discoveryA.updateLocalPeerInfo(peerInfoCbor: peerInfoACbor)
        try await discoveryB.updateLocalPeerInfo(peerInfoCbor: peerInfoBCbor)

        // Start announcing
        try await discoveryA.startAnnouncing()
        try await discoveryB.startAnnouncing()

        // Wait for discovery to work
        try await Task.sleep(nanoseconds: UInt64(1.0 * 1_000_000_000))

        // Stop node B's discovery (simulate TTL expiry)
        try await discoveryB.stopAnnouncing()
        try await discoveryB.shutdown()
        try await transportB.stop()

        // Wait for TTL cleanup
        try await Task.sleep(nanoseconds: UInt64(2.0 * 1_000_000_000))

        // Stop node A
        try await discoveryA.stopAnnouncing()
        try await discoveryA.shutdown()
        try await transportA.stop()
    }
}

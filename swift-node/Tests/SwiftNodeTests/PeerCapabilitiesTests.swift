import SwiftCommon
import SwiftFFI
@testable import SwiftNode
import RunarSerializer
import XCTest

@MainActor
final class PeerCapabilitiesTests: XCTestCase {
    private var testLogger: RunarLogger!
    private let waitStepNs: UInt64 = 100_000_000 // 100ms
    private let waitTimeoutNs: UInt64 = 5_000_000_000 // 5s

    override func setUp() async throws {
        try await super.setUp()
        LoggerConfigManager.shared.globalConfig = LoggerConfig(
            level: .trace,
            includeTimestamp: true,
            includeComponent: true,
            includeContext: true
        )
        testLogger = RunarLogger.root(component: .custom("PeerCapabilitiesTests"))
    }

    func testAddNewPeerRegistersServicesAndSubscriptions() async throws {
        let logger = testLogger.child(component: .node)

        // Build real key managers and install certificate + network key (no test-utils)
        let nodeKeys = try await NodeKeyManager()
        let caKeys = try await MobileKeyManager()

        // Install node certificate (CSR -> CA -> cert)
        let csr = try await nodeKeys.generateCsrSetupToken(logger: logger.child(component: .network))
        let cert = try await caKeys.processSetupToken(csr)
        try await nodeKeys.installCertificate(cert)

        // Generate network public key on mobile (acts as network master) and install it on mobile (matches FFI tests)
        let networkPublicKey = try await caKeys.generateNetworkDataKey()
        try await caKeys.installNetworkPublicKey(networkPublicKey)

        // Create network key message for node using node agreement public key
        let nodeAgreementPk = try await nodeKeys.getAgreementPublicKey()
        let nkm = try await caKeys.createNetworkKeyMessage(networkPublicKey: networkPublicKey, nodeAgreementPublicKey: nodeAgreementPk)
        try await nodeKeys.installNetworkKey(nkm)

        // Derive networkId as compact ID of the network public key (matches FFI tests)
        let networkId = try await caKeys.getCompactId(for: networkPublicKey)
        // Obtain the 32-byte network agreement public key (canonical for label resolver)
        let networkAgreementKey = try await nodeKeys.getNetworkAgreement(networkPublicKey: networkPublicKey)

        // Create a network config (QUIC + multicast discovery)
        let discoveryOptions = SwiftFFI.DiscoveryOptions(
            announceInterval: 1000,
            discoveryTimeout: 5000,
            debounceWindow: 2000,
            useMulticast: true,
            localNetworkOnly: true,
            multicastGroup: "224.0.0.251:5353"
        )
        let discoveryProvider = DiscoveryProviderConfig(type: "mdns", config: [:])
        let networkConfig = NetworkConfig(
            transportType: "quic",
            bindAddress: "127.0.0.1:0",
            connectionTimeoutMs: 30000,
            requestTimeoutMs: 30000,
            discoveryOptions: discoveryOptions,
            discoveryProviders: [discoveryProvider]
        )

        // Create node config using the real node keystore with installed network key
        let systemLabelConfig = LabelResolverConfig(
            labelMappings: [
                "system": LabelValue(
                    networkPublicKey: networkAgreementKey,
                    userKeySpec: nil
                )
            ]
        )
        let config = NodeConfig(defaultNetworkId: networkId)
            .withKeyManager(nodeKeys)
            .withLabelResolverConfig(systemLabelConfig)
            .withNetworkConfig(networkConfig)
        let node = try await Node.new(config: config)

        // Add a simple local service so registry is initialized properly
        let registryService = RegistryService(logger: logger, registryDelegate: node)
        try await node.addService(registryService)

        try await node.start()
        try await node.waitForServicesToStart()

        // Build a real peer NodeInfo with 1 service and 1 subscription (mirror FFI tests)
        // Create peer key manager and install certificate
        let peerKeys = try await NodeKeyManager()
        let peerCsr = try await peerKeys.generateCsrSetupToken(logger: logger.child(component: .network))
        let peerCert = try await caKeys.processSetupToken(peerCsr)
        try await peerKeys.installCertificate(peerCert)
        let peerPublicKey = try await peerKeys.getNodePublicKey()

        let actionMeta = ActionMetadata(name: "noop", description: "noop")
        let serviceMeta = ServiceMetadata(
            networkId: networkId,
            servicePath: "peer_svc",
            name: "PeerService",
            version: "1.0.0",
            description: "Test peer service",
            actions: [actionMeta],
            registrationTime: 0,
            lastStartTime: nil
        )
        let subMeta = SubscriptionMetadata(path: "\(networkId):peer_svc/evt")
        let nodeMeta = NodeMetadata(services: [serviceMeta], subscriptions: [subMeta])

        let peerInfo = NodeInfo(
            nodePublicKey: peerPublicKey,
            networkIds: [networkId],
            addresses: ["127.0.0.1:0"],
            nodeMetadata: nodeMeta,
            version: 1
        )

        // Call addNewPeer and assert service gets registered and set to running
        let remoteServices = try await node.addNewPeer(nodeInfo: peerInfo)
        XCTAssertEqual(remoteServices.count, 1)

        let serviceTopic = try TopicPath.new("peer_svc", defaultNetwork: networkId)
        let state = await node.serviceRegistry.getRemoteServiceState(servicePath: serviceTopic)
        XCTAssertEqual(state, ServiceState.running)

        // Verify subscription via test helper snapshot, then remove and assert gone
        let subTopic = try TopicPath.fromFullPath("\(networkId):peer_svc/evt")
        let peerId = CompactId.compactId(from: peerPublicKey)
        // Poll until subscription appears (async registry upsert)
        logger.trace("Asserting presence: peerId=\(peerId), path=\(subTopic.asString())")
        var beforeId: String? = nil
        var waited: UInt64 = 0
        while beforeId == nil && waited < waitTimeoutNs {
            let all = await node.serviceRegistry.getAllPeersRemoteSubscriptions()
            logger.trace("All peer subs snapshot: \(all)")
            beforeId = all[peerId]?[subTopic.asString()]
            if beforeId == nil { try? await Task.sleep(nanoseconds: waitStepNs); waited += waitStepNs }
        }
        XCTAssertNotNil(beforeId)
        let removedId = await node.serviceRegistry.removeRemotePeerSubscription(peerId: peerId, path: subTopic)
        XCTAssertEqual(removedId, beforeId)
        // Poll until removal is reflected
        logger.trace("Asserting removal: peerId=\(peerId), path=\(subTopic.asString())")
        var removedGone = false
        waited = 0
        while !removedGone && waited < waitTimeoutNs {
            let all = await node.serviceRegistry.getAllPeersRemoteSubscriptions()
            removedGone = (all[peerId]?[subTopic.asString()] == nil)
            if !removedGone { try? await Task.sleep(nanoseconds: waitStepNs); waited += waitStepNs }
        }
        XCTAssertTrue(removedGone)

        // Cleanup
        try await node.stop()
    }

    func testUpdatePeerCapabilitiesAddsAndRemoves() async throws {
        let logger = testLogger.child(component: .node)

        // Build real key managers and install certificate + network key (no test-utils)
        let nodeKeys = try await NodeKeyManager()
        let caKeys = try await MobileKeyManager()

        let discoveryOptions = SwiftFFI.DiscoveryOptions(
            announceInterval: 1000,
            discoveryTimeout: 5000,
            debounceWindow: 2000,
            useMulticast: true,
            localNetworkOnly: true,
            multicastGroup: "224.0.0.251:5353"
        )
        let discoveryProvider = DiscoveryProviderConfig(type: "mdns", config: [:])
        let networkConfig = NetworkConfig(
            transportType: "quic",
            bindAddress: "127.0.0.1:0",
            connectionTimeoutMs: 30000,
            requestTimeoutMs: 30000,
            discoveryOptions: discoveryOptions,
            discoveryProviders: [discoveryProvider]
        )

        // Install node certificate
        let csr = try await nodeKeys.generateCsrSetupToken(logger: logger.child(component: .network))
        let cert = try await caKeys.processSetupToken(csr)
        try await nodeKeys.installCertificate(cert)

        // Generate and install network key for node
        let networkPublicKey = try await caKeys.generateNetworkDataKey()
        try await caKeys.installNetworkPublicKey(networkPublicKey)
        let nodeAgreementPk = try await nodeKeys.getAgreementPublicKey()
        let nkm = try await caKeys.createNetworkKeyMessage(networkPublicKey: networkPublicKey, nodeAgreementPublicKey: nodeAgreementPk)
        try await nodeKeys.installNetworkKey(nkm)

        // Network ID string as compact ID of the network public key
        let networkId = try await caKeys.getCompactId(for: networkPublicKey)
        // Obtain the 32-byte network agreement public key (canonical for label resolver)
        let networkAgreementKey = try await nodeKeys.getNetworkAgreement(networkPublicKey: networkPublicKey)

        let systemLabelConfig = LabelResolverConfig(
            labelMappings: [
                "system": LabelValue(
                    networkPublicKey: networkAgreementKey,
                    userKeySpec: nil
                )
            ]
        )
        let config = NodeConfig(defaultNetworkId: networkId)
            .withKeyManager(nodeKeys)
            .withLabelResolverConfig(systemLabelConfig)
            .withNetworkConfig(networkConfig)
        let node = try await Node.new(config: config)

        let registryService = RegistryService(logger: logger, registryDelegate: node)
        try await node.addService(registryService)
        try await node.start()
        try await node.waitForServicesToStart()

        // networkId defined above
        let peerKeys = try await NodeKeyManager()
        let peerCsr = try await peerKeys.generateCsrSetupToken(logger: logger.child(component: .network))
        let peerCert = try await caKeys.processSetupToken(peerCsr)
        try await peerKeys.installCertificate(peerCert)
        let peerPublicKey = try await peerKeys.getNodePublicKey()

        // OLD peer: has svcA and subscription A
        let svcA = ServiceMetadata(
            networkId: networkId,
            servicePath: "svcA",
            name: "A",
            version: "1",
            description: "A",
            actions: [ActionMetadata(name: "noop", description: "")],
            registrationTime: 0,
            lastStartTime: nil
        )
        let subA = SubscriptionMetadata(path: "\(networkId):svcA/evt")
        let oldMeta = NodeMetadata(services: [svcA], subscriptions: [subA])
        let oldPeer = NodeInfo(
            nodePublicKey: peerPublicKey,
            networkIds: [networkId],
            addresses: ["127.0.0.1:0"],
            nodeMetadata: oldMeta,
            version: 1
        )

        // NEW peer: has svcB and subscription B (svcA/subA removed)
        let svcB = ServiceMetadata(
            networkId: networkId,
            servicePath: "svcB",
            name: "B",
            version: "1",
            description: "B",
            actions: [ActionMetadata(name: "noop", description: "")],
            registrationTime: 0,
            lastStartTime: nil
        )
        let subB = SubscriptionMetadata(path: "\(networkId):svcB/evt")
        let newMeta = NodeMetadata(services: [svcB], subscriptions: [subB])
        let newPeer = NodeInfo(
            nodePublicKey: peerPublicKey,
            networkIds: [networkId],
            addresses: ["127.0.0.1:0"],
            nodeMetadata: newMeta,
            version: 1
        )

        // First, add old peer so we have initial state (svcA registered, subA present)
        _ = try await node.addNewPeer(nodeInfo: oldPeer)
        let peerId = CompactId.compactId(from: peerPublicKey)
        let subATopic = try TopicPath.fromFullPath("\(networkId):svcA/evt")
        // Poll until initial subA appears
        logger.trace("Asserting initial presence: peerId=\(peerId), subA=\(subATopic.asString())")
        var subAPresent = false
        var waited: UInt64 = 0
        while !subAPresent && waited < waitTimeoutNs {
            let all = await node.serviceRegistry.getAllPeersRemoteSubscriptions()
            subAPresent = (all[peerId]?[subATopic.asString()] != nil)
            if !subAPresent { try? await Task.sleep(nanoseconds: waitStepNs); waited += waitStepNs }
        }
        XCTAssertTrue(subAPresent)

        // Now update capabilities to switch to svcB/subB
        try await node.updatePeerCapabilities(oldPeer: oldPeer, newPeer: newPeer)

        // Assert svcB is running
        let svcBTopic = try TopicPath.new("svcB", defaultNetwork: networkId)
        let svcBState = await node.serviceRegistry.getRemoteServiceState(servicePath: svcBTopic)
        XCTAssertEqual(svcBState, ServiceState.running)

        // After update: subA removed, subB present
        let subBTopic = try TopicPath.fromFullPath("\(networkId):svcB/evt")
        // Poll until subA removed and subB present
        logger.trace("Asserting update: peerId=\(peerId), removed=\(subATopic.asString()), present=\(subBTopic.asString())")
        var subARemoved = false
        var subBId: String? = nil
        waited = 0
        while (!subARemoved || subBId == nil) && waited < waitTimeoutNs {
            let all = await node.serviceRegistry.getAllPeersRemoteSubscriptions()
            logger.trace("All peer subs snapshot (after update): \(all)")
            subARemoved = (all[peerId]?[subATopic.asString()] == nil)
            subBId = all[peerId]?[subBTopic.asString()]
            if (!subARemoved || subBId == nil) { try? await Task.sleep(nanoseconds: waitStepNs); waited += waitStepNs }
        }
        XCTAssertTrue(subARemoved)
        XCTAssertNotNil(subBId)
        // Removal returns same id and disappears from snapshot
        let removedB = await node.serviceRegistry.removeRemotePeerSubscription(peerId: peerId, path: subBTopic)
        XCTAssertEqual(removedB, subBId)
        // Poll until subB disappears
        logger.trace("Asserting final removal: peerId=\(peerId), subB=\(subBTopic.asString())")
        var subBGone = false
        waited = 0
        while !subBGone && waited < waitTimeoutNs {
            let all = await node.serviceRegistry.getAllPeersRemoteSubscriptions()
            subBGone = (all[peerId]?[subBTopic.asString()] == nil)
            if !subBGone { try? await Task.sleep(nanoseconds: waitStepNs); waited += waitStepNs }
        }
        XCTAssertTrue(subBGone)

        try await node.stop()
    }
}



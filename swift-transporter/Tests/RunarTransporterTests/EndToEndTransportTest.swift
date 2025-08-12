import RunarKeys
@testable import RunarTransporter
import SwiftCommon
import XCTest

@available(macOS 12.0, iOS 15.0, *)
final class EndToEndTransportTest: XCTestCase {
    private var transport1: NetworkQuicTransporter!
    private var transport2: NetworkQuicTransporter!
    private var logger: RunarLogger!
    private var node1PublicKey: Data!
    private var node2PublicKey: Data!
    private var node1Id: String!
    private var node2Id: String!
    private var nodeKeyManager1: MobileKeyManager!
    private var nodeKeyManager2: MobileKeyManager!

    // Message tracking for validation
    private var transport1Messages: [RunarNetworkMessage] = []
    private var transport2Messages: [RunarNetworkMessage] = []

    override func setUp() async throws {
        logger = RunarLogger(subsystem: "com.runar.transporter.test", category: "E2ETest")

        // Create message handlers that track received messages
        let handler1 = TestMessageHandler { [weak self] message in
            self?.transport1Messages.append(message)
        }

        let handler2 = TestMessageHandler { [weak self] message in
            self?.transport2Messages.append(message)
        }

        // Prepare certificate infrastructure: one CA and two nodes
        let mobileCA = try MobileKeyManager(logger: ConsoleLogger(prefix: "E2E-CA"))
        _ = try mobileCA.initializeUserRootKey()
        try mobileCA.createCACertificate()

        nodeKeyManager1 = try MobileKeyManager(logger: ConsoleLogger(prefix: "E2E-Node1"))
        _ = try nodeKeyManager1.initializeUserRootKey()
        let setupToken1 = try nodeKeyManager1.generateCSR()
        let cert1 = try mobileCA.processSetupToken(setupToken1)
        try nodeKeyManager1.installCertificate(cert1)

        nodeKeyManager2 = try MobileKeyManager(logger: ConsoleLogger(prefix: "E2E-Node2"))
        _ = try nodeKeyManager2.initializeUserRootKey()
        let setupToken2 = try nodeKeyManager2.generateCSR()
        let cert2 = try mobileCA.processSetupToken(setupToken2)
        try nodeKeyManager2.installCertificate(cert2)

        // Compute real node public keys and ids
        node1PublicKey = nodeKeyManager1.getNodePublicKey()
        node2PublicKey = nodeKeyManager2.getNodePublicKey()
        node1Id = CryptoUtils.compactId(node1PublicKey)
        node2Id = CryptoUtils.compactId(node2PublicKey)

        // Create node info for both transports
        let node1Info = RunarNodeInfo(
            nodePublicKey: node1PublicKey,
            addresses: ["127.0.0.1:50069"],
            services: []
        )

        let node2Info = RunarNodeInfo(
            nodePublicKey: node2PublicKey,
            addresses: ["127.0.0.1:50044"],
            services: []
        )

        // Create transport options including certificates and SecKey
        let node1CertConfig = try nodeKeyManager1.getQuicCertificateConfig()
        let node2CertConfig = try nodeKeyManager2.getQuicCertificateConfig()

        let options1 = NetworkQuicTransportOptions(
            verifyCertificates: true,
            keepAliveInterval: 15.0,
            connectionIdleTimeout: 60.0,
            streamIdleTimeout: 30.0,
            maxIdleStreamsPerPeer: 10,
            certificates: node1CertConfig.certificateChain,
            secKey: node1CertConfig.secKey,
            mobileKeyManager: nodeKeyManager1
        )
        let options2 = NetworkQuicTransportOptions(
            verifyCertificates: true,
            keepAliveInterval: 15.0,
            connectionIdleTimeout: 60.0,
            streamIdleTimeout: 30.0,
            maxIdleStreamsPerPeer: 10,
            certificates: node2CertConfig.certificateChain,
            secKey: node2CertConfig.secKey,
            mobileKeyManager: nodeKeyManager2
        )

        // Initialize transports
        transport1 = NetworkQuicTransporter(
            nodeInfo: node1Info,
            bindAddress: "127.0.0.1:50069",
            messageHandler: handler1,
            options: options1,
            logger: logger
        )

        transport2 = NetworkQuicTransporter(
            nodeInfo: node2Info,
            bindAddress: "127.0.0.1:50044",
            messageHandler: handler2,
            options: options2,
            logger: logger
        )
    }

    override func tearDown() async throws {
        await transport1?.stop()
        await transport2?.stop()
        transport1 = nil
        transport2 = nil
    }

    // Removed legacy overlapping E2E. Coverage lives in EndToEndTests.testEndToEndQuicTransportWithTLS
}

// MARK: - Test Message Handler

@available(macOS 12.0, iOS 15.0, *)
private class TestMessageHandler: MessageHandlerProtocol {
    private let messageCallback: (RunarNetworkMessage) -> Void

    init(messageCallback: @escaping (RunarNetworkMessage) -> Void) {
        self.messageCallback = messageCallback
    }

    func handleMessage(_ message: RunarNetworkMessage) {
        messageCallback(message)
    }

    func peerConnected(_: RunarNodeInfo) {
        // Track peer connections if needed
    }

    func peerDisconnected(_: String) {
        // Track peer disconnections if needed
    }
}

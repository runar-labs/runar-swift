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
    private var nodeSecKey1: SecKey!
    private var nodeSecKey2: SecKey!

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
        let mobileKM = RunarKeys.MobileKeyManager()
        let ca = try mobileKM.createCA(subjectCN: "Runar Test CA")

        nodeSecKey1 = try mobileKM.generateNodeIdentity(label: "node1-\(UUID().uuidString)")
        let node1Pub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: nodeSecKey1)
        let node1IdLocal = RunarKeys.Ids.compactId(node1Pub)
        let csr1 = try mobileKM.buildCSR(signingKey: nodeSecKey1, subjectCN: node1IdLocal, nodeIdSAN: node1IdLocal)
        let cert1 = try mobileKM.issueLeaf(from: ca, csrDER: csr1, subjectOverrideCN: node1IdLocal, sanDNS: [node1IdLocal], validityDays: 180)

        nodeSecKey2 = try mobileKM.generateNodeIdentity(label: "node2-\(UUID().uuidString)")
        let node2Pub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: nodeSecKey2)
        let node2IdLocal = RunarKeys.Ids.compactId(node2Pub)
        let csr2 = try mobileKM.buildCSR(signingKey: nodeSecKey2, subjectCN: node2IdLocal, nodeIdSAN: node2IdLocal)
        let cert2 = try mobileKM.issueLeaf(from: ca, csrDER: csr2, subjectOverrideCN: node2IdLocal, sanDNS: [node2IdLocal], validityDays: 180)

        // Compute real node public keys and ids
        node1PublicKey = node1Pub
        node2PublicKey = node2Pub
        node1Id = node1IdLocal
        node2Id = node2IdLocal

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
        let node1Chain = [RunarKeys.CertificateUtils.toDER(cert1), RunarKeys.CertificateUtils.toDER(ca.generated.certificate)]
        let node2Chain = [RunarKeys.CertificateUtils.toDER(cert2), RunarKeys.CertificateUtils.toDER(ca.generated.certificate)]

        let options1 = NetworkQuicTransportOptions(
            verifyCertificates: true,
            keepAliveInterval: 15.0,
            connectionIdleTimeout: 60.0,
            streamIdleTimeout: 30.0,
            maxIdleStreamsPerPeer: 10,
            certificates: node1Chain,
            secKey: nodeSecKey1,
            mobileKeyManager: nil
        )
        let options2 = NetworkQuicTransportOptions(
            verifyCertificates: true,
            keepAliveInterval: 15.0,
            connectionIdleTimeout: 60.0,
            streamIdleTimeout: 30.0,
            maxIdleStreamsPerPeer: 10,
            certificates: node2Chain,
            secKey: nodeSecKey2,
            mobileKeyManager: nil
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

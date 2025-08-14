import RunarKeys
@testable import RunarTransporter
import SwiftCommon
import XCTest

@available(macOS 12.0, iOS 15.0, *)
final class SimpleConnectionTest: XCTestCase {
    private var transport1: NetworkQuicTransporter!
    private var transport2: NetworkQuicTransporter!
    private var logger: RunarLogger!
    private var node1PublicKey: Data!
    private var node2PublicKey: Data!
    private var node1Id: String!
    private var node2Id: String!

    override func setUp() async throws {
        logger = RunarLogger(subsystem: "com.runar.transporter.test", category: "SimpleConnectionTest")

        // Create simple message handlers
        let handler1 = TestMessageHandler { message in
            self.logger.info("Transport1 received: \(message.messageType)")
        }

        let handler2 = TestMessageHandler { message in
            self.logger.info("Transport2 received: \(message.messageType)")
        }

        // Set up certificate infrastructure: CA and two nodes
        let caKM = RunarKeys.MobileKeyManager()
        let ca = try caKM.createCA(subjectCN: "Runar Test CA")

        let nodeSecKey1 = try caKM.generateNodeIdentity(label: "node1-\(UUID().uuidString)")
        let node1Pub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: nodeSecKey1)
        let node1IdLocal = RunarKeys.Ids.compactId(node1Pub)
        let csr1 = try caKM.buildCSR(signingKey: nodeSecKey1, subjectCN: node1IdLocal, nodeIdSAN: node1IdLocal)
        let cert1 = try caKM.issueLeaf(from: ca, csrDER: csr1, subjectOverrideCN: node1IdLocal, sanDNS: [node1IdLocal], validityDays: 180)

        let nodeSecKey2 = try caKM.generateNodeIdentity(label: "node2-\(UUID().uuidString)")
        let node2Pub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: nodeSecKey2)
        let node2IdLocal = RunarKeys.Ids.compactId(node2Pub)
        let csr2 = try caKM.buildCSR(signingKey: nodeSecKey2, subjectCN: node2IdLocal, nodeIdSAN: node2IdLocal)
        let cert2 = try caKM.issueLeaf(from: ca, csrDER: csr2, subjectOverrideCN: node2IdLocal, sanDNS: [node2IdLocal], validityDays: 180)

        // Real node keys and ids
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
            addresses: ["127.0.0.1:50070"],
            services: []
        )

        // Create transport options with certificates and MobileKeyManager
        let cfg1Chain = [RunarKeys.CertificateUtils.toDER(cert1), RunarKeys.CertificateUtils.toDER(ca.generated.certificate)]
        let cfg2Chain = [RunarKeys.CertificateUtils.toDER(cert2), RunarKeys.CertificateUtils.toDER(ca.generated.certificate)]
        let options1 = NetworkQuicTransportOptions(
            verifyCertificates: true,
            keepAliveInterval: 15,
            connectionIdleTimeout: 60,
            streamIdleTimeout: 30,
            maxIdleStreamsPerPeer: 10,
            certificates: cfg1Chain,
            secKey: nodeSecKey1,
            mobileKeyManager: nil
        )
        let options2 = NetworkQuicTransportOptions(
            verifyCertificates: true,
            keepAliveInterval: 15,
            connectionIdleTimeout: 60,
            streamIdleTimeout: 30,
            maxIdleStreamsPerPeer: 10,
            certificates: cfg2Chain,
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
            bindAddress: "127.0.0.1:50070",
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

    func testSimpleConnection() async throws {
        do {
            try await runWithTimeout(10) {
                self.logger.info("🚀 Starting simple connection test")

                // Step 1: Start both transports
                self.logger.info("📡 Starting transport services...")
                try await self.transport1.start()
                self.logger.info("✅ Transport1 started")
                try await self.transport2.start()
                self.logger.info("✅ Transport2 started")

                // Allow transports to initialize
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                self.logger.info("⏰ After initialization delay")

                // Step 2: Try to connect transport1 to transport2
                self.logger.info("🔗 Connecting transport1 to transport2...")

                let peer2Info = RunarPeerInfo(
                    publicKey: self.node2PublicKey,
                    addresses: ["127.0.0.1:50070"]
                )

                do {
                    self.logger.info("🔗 Attempting connection (expect success with correct SPKI pin)...")
                    try await self.transport1.connect(to: peer2Info)
                    self.logger.info("✅ Connection attempt completed")
                } catch {
                    self.logger.error("❌ Connection failed: \(error)")
                    XCTFail("Connection failed: \(error)")
                }

                // Step 3: Check connection status
                let isConnected = await self.transport1.isConnected(to: self.node2Id)
                self.logger.info("🔍 Connection status: \(isConnected)")

                XCTAssertTrue(isConnected, "Connection should be established")
                // Step 4: Negative pinning test: try wrong expected key (flip one byte)
                let wrongKey = Data(self.node2PublicKey.enumerated().map { i, b in i == 0 ? b ^ 0xFF : b })
                let badPeerInfo = RunarPeerInfo(publicKey: wrongKey, addresses: ["127.0.0.1:50070"])
                do {
                    self.logger.info("🔗 Attempting connection with WRONG SPKI (should fail)...")
                    try await self.transport1.connect(to: badPeerInfo)
                    XCTFail("Connection should have failed due to SPKI pin mismatch")
                } catch {
                    self.logger.info("✅ Expected failure with wrong SPKI: \(error)")
                }
            }
        } catch {
            XCTFail("Test failed or timed out: \(error)")
        }
    }
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

import Foundation
import SwiftCommon
import RunarKeys
import RunarTransporter

@main
struct QuicITMain {
    static func main() {
        let group = DispatchGroup()
        group.enter()
        var exitCode: Int32 = 0
        fputs("[QuicIT] booting...\n", stderr)
        Task.detached(priority: .userInitiated) {
            let logger = RunarLogger(subsystem: "com.runar.transporter", category: "QuicIT")
            fputs("[QuicIT] starting...\n", stderr)
            do {
            // Lightweight self-test path to validate BinaryMessageEncoder without Keychain/QUIC
            if ProcessInfo.processInfo.environment["RUNAR_SELFTEST"] == "1" {
                let dummyPk = Data(repeating: 0x42, count: 97)
                let node = RunarNodeInfo(nodePublicKey: dummyPk, networkIds: ["it"], addresses: ["127.0.0.1:9999"], services: [])
                let enc = try BinaryMessageEncoder.encodeNodeInfo(node)
                let dec = try BinaryMessageEncoder.decodeNodeInfo(from: enc)
                guard dec.nodePublicKey == dummyPk else { fputs("SELFTEST mismatch\n", stderr); exit(10) }
                fputs("SELFTEST ok\n", stderr)
                exit(0)
            }
            let mobileCA = try MobileKeyManager(logger: ConsoleLogger(prefix: "IT-CA"))
            _ = try mobileCA.initializeUserRootKey()
            try mobileCA.createCACertificate()

            let km1 = try MobileKeyManager(logger: ConsoleLogger(prefix: "IT-Node1"))
            _ = try km1.initializeUserRootKey()
            let st1 = try km1.generateCSR()
            let cert1 = try mobileCA.processSetupToken(st1)
            try km1.installCertificate(cert1)

            let km2 = try MobileKeyManager(logger: ConsoleLogger(prefix: "IT-Node2"))
            _ = try km2.initializeUserRootKey()
            let st2 = try km2.generateCSR()
            let cert2 = try mobileCA.processSetupToken(st2)
            try km2.installCertificate(cert2)

            let node1Pk = km1.getNodePublicKey()
            let node2Pk = km2.getNodePublicKey()
            let node1Id = CryptoUtils.compactId(node1Pk)
            let node2Id = CryptoUtils.compactId(node2Pk)

            let cfg1 = try km1.getQuicCertificateConfig()
            let cfg2 = try km2.getQuicCertificateConfig()
            let opt1 = NetworkQuicTransportOptions(
                verifyCertificates: true,
                keepAliveInterval: 15,
                connectionIdleTimeout: 60,
                streamIdleTimeout: 30,
                maxIdleStreamsPerPeer: 10,
                certificates: cfg1.certificateChain,
                secKey: cfg1.secKey,
                mobileKeyManager: km1
            )
            let opt2 = NetworkQuicTransportOptions(
                verifyCertificates: true,
                keepAliveInterval: 15,
                connectionIdleTimeout: 60,
                streamIdleTimeout: 30,
                maxIdleStreamsPerPeer: 10,
                certificates: cfg2.certificateChain,
                secKey: cfg2.secKey,
                mobileKeyManager: km2
            )

            // Explicit handlers we can inspect later
            let h1 = SimpleHandler(nodeId: node1Id)
            let h2 = SimpleHandler(nodeId: node2Id)

            // Try to bind two high ports, retrying on EADDRINUSE
            let basePort: UInt16 = 59000
            var chosenP1: UInt16 = 0
            var chosenP2: UInt16 = 0
            var t1: NetworkQuicTransporter!
            var t2: NetworkQuicTransporter!
            var started = false
            for step in 0..<50 { // 50 attempts → 100 ports scanned
                let p1 = basePort &+ UInt16(step * 2)
                let p2 = p1 &+ 1

                let node1Info = RunarNodeInfo(
                    nodePublicKey: node1Pk,
                    networkIds: ["it"],
                    addresses: ["localhost:\(p1)"],
                    services: []
                )
                let node2Info = RunarNodeInfo(
                    nodePublicKey: node2Pk,
                    networkIds: ["it"],
                    addresses: ["localhost:\(p2)"],
                    services: []
                )

                let candT1 = NetworkQuicTransporter(
                    nodeInfo: node1Info,
                    bindAddress: "localhost:\(p1)",
                    messageHandler: h1,
                    options: opt1,
                    logger: logger
                )
                let candT2 = NetworkQuicTransporter(
                    nodeInfo: node2Info,
                    bindAddress: "localhost:\(p2)",
                    messageHandler: h2,
                    options: opt2,
                    logger: logger
                )

                do {
                    try await candT1.start()
                    try await candT2.start()
                    t1 = candT1
                    t2 = candT2
                    chosenP1 = p1
                    chosenP2 = p2
                    started = true
                    break
                } catch {
                    fputs("[QuicIT] Port pair (\(p1),\(p2)) in use or failed: \(error)\n", stderr)
                    // Ensure clean state before retrying
                    await candT1.stop()
                    await candT2.stop()
                    continue
                }
            }

            guard started else {
                fputs("[QuicIT] Could not bind any port pair\n", stderr)
                exit(1)
            }

            // Give listeners a moment
            try await Task.sleep(nanoseconds: 800_000_000)

            // Build peers using the chosen ports
            let p1Peer = RunarPeerInfo(publicKey: node1Pk, addresses: ["localhost:\(chosenP1)"]) // peer for node1
            let p2Peer = RunarPeerInfo(publicKey: node2Pk, addresses: ["localhost:\(chosenP2)"]) // peer for node2

            // Cross-connect
            try await t1.connect(to: p2Peer)
            try await t2.connect(to: p1Peer)
            try await Task.sleep(nanoseconds: 1_500_000_000)

            // Send a request from node1 to node2
            let req = RunarNetworkMessage(
                sourceNodeId: node1Id,
                destinationNodeId: node2Id,
                messageType: MessageTypes.REQUEST,
                payloads: [NetworkMessagePayloadItem(path: "/it/get", valueBytes: Data("ok".utf8), correlationId: "it-1")]
            )
            try await t1.send(message: req)
            try await Task.sleep(nanoseconds: 1_000_000_000)

            // Validate
            let t1Connected = await t1.isConnected(to: node2Id)
            let t2Connected = await t2.isConnected(to: node1Id)
            guard t1Connected || t2Connected else {
                fputs("Connection not established\n", stderr); exit(2)
            }
            let hasHandshake = (h1.messages.contains { $0.messageType == MessageTypes.HANDSHAKE }) || (h2.messages.contains { $0.messageType == MessageTypes.HANDSHAKE })
            let hasRequest = h2.messages.contains { $0.messageType == MessageTypes.REQUEST }
            guard hasHandshake else { fputs("No handshake\n", stderr); exit(3) }
            guard hasRequest else { fputs("No request received\n", stderr); exit(4) }

            await t1.stop()
            await t2.stop()
            print("✅ QUIC IT ok")
            exitCode = 0
        } catch {
            fputs("IT error: \(error)\n", stderr)
            exitCode = 1
        }
            group.leave()
        }
        group.wait()
        exit(exitCode)
    }
}

final class SimpleHandler: MessageHandlerProtocol {
    let nodeId: String
    var messages: [RunarNetworkMessage] = []
    init(nodeId: String) { self.nodeId = nodeId }
    func handleMessage(_ message: RunarNetworkMessage) { messages.append(message) }
    func peerConnected(_ peerInfo: RunarNodeInfo) {}
    func peerDisconnected(_ peerId: String) {}
}

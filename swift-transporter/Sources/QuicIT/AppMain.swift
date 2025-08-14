import Foundation
import RunarKeys
import RunarTransporter
import SwiftCommon

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
                let mobileKM = RunarKeys.MobileKeyManager()
                let ca = try mobileKM.createCA(subjectCN: "Runar Test CA")

                let nodeSecKey1 = try mobileKM.generateNodeIdentity(label: "node1-\(UUID().uuidString)")
                let node1Pub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: nodeSecKey1)
                let node1Id = RunarKeys.Ids.compactId(node1Pub)
                let csr1 = try mobileKM.buildCSR(signingKey: nodeSecKey1, subjectCN: node1Id, nodeIdSAN: node1Id)
                let cert1 = try mobileKM.issueLeaf(from: ca, csrDER: csr1, subjectOverrideCN: node1Id, sanDNS: [node1Id], validityDays: 180)

                let nodeSecKey2 = try mobileKM.generateNodeIdentity(label: "node2-\(UUID().uuidString)")
                let node2Pub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: nodeSecKey2)
                let node2Id = RunarKeys.Ids.compactId(node2Pub)
                let csr2 = try mobileKM.buildCSR(signingKey: nodeSecKey2, subjectCN: node2Id, nodeIdSAN: node2Id)
                let cert2 = try mobileKM.issueLeaf(from: ca, csrDER: csr2, subjectOverrideCN: node2Id, sanDNS: [node2Id], validityDays: 180)

                let node1Pk = node1Pub
                let node2Pk = node2Pub

                let cfg1Chain = [RunarKeys.CertificateUtils.toDER(cert1), RunarKeys.CertificateUtils.toDER(ca.generated.certificate)]
                let cfg2Chain = [RunarKeys.CertificateUtils.toDER(cert2), RunarKeys.CertificateUtils.toDER(ca.generated.certificate)]
                let opt1 = NetworkQuicTransportOptions(
                    verifyCertificates: true,
                    keepAliveInterval: 15,
                    connectionIdleTimeout: 60,
                    streamIdleTimeout: 30,
                    maxIdleStreamsPerPeer: 10,
                    certificates: cfg1Chain,
                    secKey: nodeSecKey1,
                    mobileKeyManager: nil
                )
                let opt2 = NetworkQuicTransportOptions(
                    verifyCertificates: true,
                    keepAliveInterval: 15,
                    connectionIdleTimeout: 60,
                    streamIdleTimeout: 30,
                    maxIdleStreamsPerPeer: 10,
                    certificates: cfg2Chain,
                    secKey: nodeSecKey2,
                    mobileKeyManager: nil
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
                for step in 0 ..< 50 { // 50 attempts → 100 ports scanned
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
                    messageType: MessageTypes.request,
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
                let hasHandshake = (h1.messages.contains { $0.messageType == MessageTypes.handshake }) || (h2.messages.contains { $0.messageType == MessageTypes.handshake })
                let hasRequest = h2.messages.contains { $0.messageType == MessageTypes.request }
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
    func peerConnected(_: RunarNodeInfo) {}
    func peerDisconnected(_: String) {}
}

import Foundation
import RunarTransporter
import RunarKeys
import SwiftASN1
import SwiftCommon
import Crypto

@main
struct InteropE2EApp {
    static func main() async {
        let logger = RunarLogger(category: "InteropE2E")
        do {
            let km = RunarKeys.MobileKeyManager()
            let ca = try km.createCA(subjectCN: "Runar Interop CA")

            let serverKey = try km.generateNodeIdentity(label: "interop-swift-server-\(UUID().uuidString)")
            let serverPub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: serverKey)
            let serverId = RunarKeys.Ids.compactId(serverPub)
            let csrS = try km.buildCSR(signingKey: serverKey, subjectCN: serverId, nodeIdSAN: serverId)
            let serverCert = try km.issueLeaf(from: ca, csrDER: csrS, subjectOverrideCN: serverId, sanDNS: [serverId], validityDays: 30)

            let chain = [RunarKeys.CertificateUtils.toDER(serverCert), RunarKeys.CertificateUtils.toDER(ca.generated.certificate)]
            let nodeInfo = RunarNodeInfo(nodePublicKey: serverPub, networkIds: ["interop"], addresses: ["127.0.0.1:44444"], services: [])
            let options = NetworkQuicTransportOptions.withCertificates(certificates: chain, secKey: serverKey, mobileKeyManager: km, verifyCertificates: true)
            let handler = SimpleHandler()
            let transport = RunarTransporter.createQuicTransport(nodeInfo: nodeInfo, bindAddress: "127.0.0.1:44444", messageHandler: handler, options: options, logger: logger)
            try await transport.start()
            print("Swift server ready on 127.0.0.1:44444 (nodeId=\(nodeInfo.nodeId))")
            // Run until interrupted
            RunLoop.current.run()
        } catch {
            print("InteropE2E error: \(error)")
            exit(1)
        }
    }
}

final class SimpleHandler: MessageHandlerProtocol {
    func handleMessage(_ message: RunarNetworkMessage) { print("msg type=\(message.messageType)") }
    func peerConnected(_ peerInfo: RunarNodeInfo) { print("peer connected: \(peerInfo.nodeId)") }
    func peerDisconnected(_ peerId: String) { print("peer disconnected: \(peerId)") }
}



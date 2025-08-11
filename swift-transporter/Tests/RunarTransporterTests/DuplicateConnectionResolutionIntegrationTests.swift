import XCTest
import SwiftCommon
@testable import RunarTransporter

@available(macOS 12.0, iOS 15.0, *)
final class DuplicateConnectionResolutionIntegrationTests: XCTestCase {
    func testDecideKeepExistingBasedOnDesiredRole() {
        let logger = RunarLogger(subsystem: "com.runar.transporter", category: "tests")
        let nodeInfo = RunarNodeInfo(nodePublicKey: Data(repeating: 0x01, count: 32))
        let t = NetworkQuicTransporter(
            nodeInfo: nodeInfo,
            bindAddress: "localhost:0",
            messageHandler: SimpleHandler(),
            options: NetworkQuicTransportOptions.default(),
            logger: logger
        )
        let ps = PeerState(peerNodeId: "peerZ", address: "127.0.0.1:1", logger: logger)
        // Existing recorded as initiator(local)
        ps.setDupMetadata(initiatorPeerId: nodeInfo.nodeId, initiatorNonce: 0, responderPeerId: "peerZ", responderNonce: 0)

        // Case 1: desired initiator (local < peer) -> keep existing (which is initiator)
        let peerGreaterThanLocal = nodeInfo.nodeId + "zz" // ensure peerId is lexicographically greater
        let keep = t.decideKeepExisting(localId: nodeInfo.nodeId, peerId: peerGreaterThanLocal, ps: ps)
        XCTAssertTrue(keep)

        // Case 2: desired responder (local > peer) -> replace existing (since existing is initiator)
        let peerLessThanLocal = "0000" // lexicographically smaller than most random node ids
        let keep2 = t.decideKeepExisting(localId: nodeInfo.nodeId, peerId: peerLessThanLocal, ps: ps)
        XCTAssertFalse(keep2)
    }
}

private final class SimpleHandler: MessageHandlerProtocol {
    func handleMessage(_ message: RunarNetworkMessage) {}
    func peerConnected(_ peerInfo: RunarNodeInfo) {}
    func peerDisconnected(_ peerId: String) {}
}



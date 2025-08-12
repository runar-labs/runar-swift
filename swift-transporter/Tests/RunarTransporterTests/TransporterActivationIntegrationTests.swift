@testable import RunarTransporter
import SwiftCommon
import XCTest

final class TransporterActivationIntegrationTests: XCTestCase {
    func testPeerStateActivationAfterHandshakeParsing() throws {
        // Simulate that upon parsing HandshakeData, we activate the peer state
        let logger = RunarLogger(subsystem: "com.runar.transporter", category: "tests")
        let ps = PeerState(peerNodeId: "peer", address: "127.0.0.1:1", logger: logger)
        XCTAssertFalse(ps.isConnected)
        ps.activate()
        XCTAssertTrue(ps.isConnected)
    }
}

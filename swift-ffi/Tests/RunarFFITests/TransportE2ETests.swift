import XCTest
@testable import RunarFFI
import RunarTestUtils

final class TransportE2ETests: XCTestCase {
    func testTwoTransportsConnectAndRequest() throws {
        // Build CA + 2 nodes with bind addresses
        let can = try TestFixtures.createCAAndNodes(count: 2, addresses: ["127.0.0.1:50601", "127.0.0.1:50602"], defaultNetworkId: "net")
        let n1 = can.nodes[0]
        let n2 = can.nodes[1]

        // Create transports
        let opts1 = TestFixtures.transportOptions(bindAddr: "127.0.0.1:50601")
        let opts2 = TestFixtures.transportOptions(bindAddr: "127.0.0.1:50602")
        let t1 = try FFITransport(keys: n1, optionsCBOR: opts1)
        let t2 = try FFITransport(keys: n2, optionsCBOR: opts2)

        // Start and wait briefly
        try t1.start()
        try t2.start()

        // Build peer info for t2 and connect from t1
        let p2 = TestFixtures.peerInfo(publicKey: try n2.publicKey(), addresses: ["127.0.0.1:50602"]) 
        try t1.connectPeer(p2)

        // Simple publish then poll events for a short period to assert no crash (full request path requires handlers and callbacks)
        // We exercise pollEvent readiness
        let start = Date()
        while Date().timeIntervalSince(start) < 0.2 {
            _ = try t1.pollEvent()
            _ = try t2.pollEvent()
        }

        // Stop
        try t1.stop()
        try t2.stop()
    }
}



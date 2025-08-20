import XCTest
@testable import RunarFFI
import RunarTestUtils
import SwiftCBOR

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

        // Helper: poll until event of type appears (or timeout)
        func waitForEvent(_ transport: FFITransport, _ type: String, timeout: TimeInterval = 3.0) throws -> CBOR? {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let evData = try transport.pollEvent() {
                    if let cbor = try? CBOR.decode([UInt8](evData)) {
                        if case let .map(map) = cbor, let t = map[.utf8String("type")], case let .utf8String(s) = t, s == type {
                            return cbor
                        }
                    }
                }
                usleep(20_000)
            }
            return nil
        }

        // Expect PeerConnected on t1 or t2
        _ = try waitForEvent(t1, "PeerConnected")

        // Validate isConnected API
        let peerNodeId = try n2.nodeId()
        XCTAssertTrue(try t1.isConnected(peerNodeId))

        // Request path round-trip: t1 -> t2
        let path = "test:echo/req"
        let correlation = "corr-1"
        let payload = Data([1,2,3])
        try t1.request(path: path, correlationId: correlation, payload: payload, destPeerId: try n2.nodeId(), profilePublicKey: nil)

        // t2 should receive RequestReceived; reply with completeRequest
        if let reqEv = try waitForEvent(t2, "RequestReceived") {
            if case let .map(map) = reqEv,
               let reqIdV = map[.utf8String("request_id")], case let .utf8String(reqId) = reqIdV {
                // Respond with payload Data([9])
                try t2.completeRequest(requestId: reqId, responsePayload: Data([9]), profilePublicKey: nil)
            }
        }

        // t1 should receive ResponseReceived
        if let respEv = try waitForEvent(t1, "ResponseReceived") {
            if case let .map(map) = respEv,
               let corrV = map[.utf8String("correlation_id")], case let .utf8String(corrBack) = corrV {
                XCTAssertEqual(corrBack, correlation)
            }
        }

        // Publish: t1 -> t2
        let topic = "test:notify/event"
        try t1.publish(path: topic, correlationId: "c-pub", payload: Data([7]), destPeerId: nil)
        _ = try waitForEvent(t2, "EventReceived")

        // Update local node info on t1
        let updatedInfo = TestFixtures.nodeInfo(publicKey: try n1.publicKey(), addresses: ["127.0.0.1:50601"], networks: [can.defaultNetworkId], version: 1)
        try t1.updateLocalNodeInfo(updatedInfo)

        // Disconnect
        try t1.disconnectPeer(try n2.nodeId())
        _ = try waitForEvent(t1, "PeerDisconnected")
        XCTAssertFalse(try t1.isConnected(try n2.nodeId()))

        // Stop
        try t1.stop()
        try t2.stop()
    }
}



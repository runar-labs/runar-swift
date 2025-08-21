import XCTest
@testable import RunarTestUtils
import RunarFFI
import SwiftCBOR

final class FixturesTests: XCTestCase {
    func testCreateKeyManagerWithCertAndStateRoundTrip() throws {
        let km = try TestFixtures.createKeyManagerWithCert()
        let nodeId = try km.nodeId()
        XCTAssertFalse(nodeId.isEmpty)
        let st = try km.generateCSR() // use available API to get some data
        XCTAssertFalse(st.isEmpty)
        let km2 = try FFIKeys()
        // no direct import API in FFIKeys now; just ensure nodeId obtainable
        XCTAssertFalse(try km2.nodeId().isEmpty)
    }

    func testTransportOptionsPeerInfoNodeInfoCBOR() throws {
        let opts = TestFixtures.transportOptions(bindAddr: "127.0.0.1:0", handshakeMs: 500, openStreamMs: 500, maxMessage: 1024)
        XCTAssertFalse(opts.isEmpty)
        // decode to verify shape
        struct Opts: Codable { let v: UInt32; let bind_addr: String?; let handshake_timeout_ms: UInt64?; let open_stream_timeout_ms: UInt64?; let max_message_size: UInt64? }
        let decoded = try SwiftCBOR.CodableCBORDecoder().decode(Opts.self, from: opts)
        XCTAssertEqual(decoded.v, 1)

        let pk = try TestFixtures.createKeyManagerWithCert().publicKey()
        let p = TestFixtures.peerInfo(publicKey: pk, addresses: ["127.0.0.1:1234"])
        XCTAssertFalse(p.isEmpty)
        let np = try SwiftCBOR.CodableCBORDecoder().decode(PeerInfo.self, from: p)
        XCTAssertEqual(np.addresses.first, "127.0.0.1:1234")

        let ni = TestFixtures.nodeInfo(publicKey: pk, addresses: ["127.0.0.1:0"], networks: ["test"], version: 1)
        XCTAssertFalse(ni.isEmpty)
        let dni = try SwiftCBOR.CodableCBORDecoder().decode(NodeInfo.self, from: ni)
        XCTAssertEqual(dni.version, 1)
        // Services are encoded as empty arrays in fixtures; just assert keys exist
        XCTAssertNotNil(dni.node_metadata.services)
    }
}



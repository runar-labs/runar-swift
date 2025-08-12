import Foundation
@testable import RunarTransporter
import XCTest

@available(macOS 12.0, iOS 15.0, *)
final class HandshakeCborTests: XCTestCase {
    func testEncodeDecodeHandshakeData() throws {
        let nodeInfo = RunarNodeInfo(
            nodePublicKey: Data(repeating: 0xAA, count: 32),
            networkIds: ["net"],
            addresses: ["127.0.0.1:9999"],
            services: [],
            version: 7,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let hs = HandshakeData(nodeInfo: nodeInfo, nonce: 0xDEAD_BEEF, role: .initiator)

        let encoded = try CborMessageEncoder.encodeHandshake(hs)
        let decoded = try CborMessageDecoder.decodeHandshake(from: encoded)

        XCTAssertEqual(decoded.nonce, 0xDEAD_BEEF)
        XCTAssertEqual(decoded.role, .initiator)
        XCTAssertEqual(decoded.nodeInfo.nodePublicKey, nodeInfo.nodePublicKey)
        XCTAssertEqual(decoded.nodeInfo.networkIds, ["net"])
        XCTAssertEqual(decoded.nodeInfo.addresses, ["127.0.0.1:9999"])
        XCTAssertEqual(decoded.nodeInfo.version, 7)
        XCTAssertEqual(
            decoded.nodeInfo.createdAt.timeIntervalSince1970,
            nodeInfo.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }
}

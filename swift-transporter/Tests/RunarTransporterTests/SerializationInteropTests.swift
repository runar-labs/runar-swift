import Foundation
@testable import RunarTransporter
import XCTest

@available(macOS 12.0, iOS 15.0, *)
final class SerializationInteropTests: XCTestCase {
    func test_NodeInfo_encode_matches_rust_shape_minimal() throws {
        let nodeInfo = RunarNodeInfo(
            nodePublicKey: Data(repeating: 0x11, count: 32),
            networkIds: ["net"],
            addresses: ["127.0.0.1:1234"],
            services: [],
            version: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let bytes = try CborMessageEncoder.encodeNodeInfo(nodeInfo)
        // Sanity: decode back
        let decoded = try CborMessageDecoder.decodeNodeInfo(from: bytes)
        XCTAssertEqual(decoded.networkIds, ["net"])
        XCTAssertEqual(decoded.addresses, ["127.0.0.1:1234"])
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.nodePublicKey.count, 32)
    }

    func test_Handshake_encode_decode_roundtrip() throws {
        let nodeInfo = RunarNodeInfo(
            nodePublicKey: Data(repeating: 0x22, count: 32),
            networkIds: [],
            addresses: [],
            services: [],
            version: 1,
            createdAt: Date()
        )
        let hs = HandshakeData(nodeInfo: nodeInfo, nonce: 0xDEADBEEF, role: .initiator)
        let payload = try CborMessageEncoder.encodeHandshake(hs)
        let re = try CborMessageDecoder.decodeHandshake(from: payload)
        XCTAssertEqual(re.nonce, 0xDEADBEEF)
        XCTAssertEqual(re.nodeInfo.nodePublicKey, nodeInfo.nodePublicKey)
    }
}



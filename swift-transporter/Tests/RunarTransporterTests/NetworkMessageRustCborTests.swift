import Foundation
@testable import RunarTransporter
import XCTest

@available(macOS 12.0, iOS 15.0, *)
final class NetworkMessageRustCborHandshakeTests: XCTestCase {
    func testHandshakeNetworkMessageCBORRoundtrip() throws {
        // Build minimal NodeInfo
        let nodeInfo = RunarNodeInfo(
            nodePublicKey: Data(repeating: 0x11, count: 32),
            networkIds: ["net1"],
            addresses: ["127.0.0.1:12345"],
            services: [],
            version: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let hs = HandshakeData(nodeInfo: nodeInfo, nonce: 0xAABBCCDD, role: .initiator)
        let payload = NetworkMessagePayloadItem(
            path: "handshake",
            valueBytes: try CborMessageEncoder.encodeHandshake(hs),
            correlationId: "corr-1"
        )
        let msg = RunarNetworkMessage(
            sourceNodeId: nodeInfo.nodeId,
            destinationNodeId: "peer-xyz",
            messageType: MessageTypes.handshake,
            payloads: [payload]
        )

        // Encode using Rust-aligned codec
        let bytes = try TransportWireCodec.encodeBody(from: msg)
        // Log hex for debugging interop
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        print("CBOR(NetworkMessage/handshake) hex=\(hex)")

        // Decode back and validate
        let decoded = try TransportWireCodec.decodeBody(to: bytes)
        XCTAssertEqual(decoded.messageType, MessageTypes.handshake)
        XCTAssertEqual(decoded.payloads.count, 1)
        let hsDecoded = try CborMessageDecoder.decodeHandshake(from: decoded.payloads[0].valueBytes)
        XCTAssertEqual(hsDecoded.nonce, 0xAABBCCDD)
        XCTAssertEqual(hsDecoded.nodeInfo.addresses, nodeInfo.addresses)
    }
}

final class NetworkMessageRustCborTests: XCTestCase {
    func testEncodeDecodeRustNetworkMessage() throws {
        let p1 = PayloadWithContext(
            path: "/api/get",
            valueBytes: Data([0x11, 0x22]),
            correlationId: "c1",
            context: MessageContextSwift(profilePublicKey: Data([0xAA]))
        )
        let p2 = PayloadWithContext(
            path: "/api/evt",
            valueBytes: Data([0x33]),
            correlationId: "c2",
            context: nil
        )
        let encoded = try CborMessageEncoder.encodeNetworkMessageRust(
            sourceNodeId: "src",
            destinationNodeId: "dst",
            messageTypeU32: 4,
            payloads: [p1, p2]
        )
        let decoded = try CborMessageDecoder.decodeNetworkMessageRust(from: encoded)
        XCTAssertEqual(decoded.sourceNodeId, "src")
        XCTAssertEqual(decoded.destinationNodeId, "dst")
        XCTAssertEqual(decoded.messageType, 4)
        XCTAssertEqual(decoded.payloads.count, 2)
        XCTAssertEqual(decoded.payloads[0].path, "/api/get")
        XCTAssertEqual(decoded.payloads[0].valueBytes, Data([0x11, 0x22]))
        XCTAssertEqual(decoded.payloads[0].correlationId, "c1")
        XCTAssertEqual(decoded.payloads[0].context?.profilePublicKey, Data([0xAA]))
        XCTAssertEqual(decoded.payloads[1].path, "/api/evt")
        XCTAssertEqual(decoded.payloads[1].valueBytes, Data([0x33]))
        XCTAssertEqual(decoded.payloads[1].correlationId, "c2")
        XCTAssertNil(decoded.payloads[1].context)
    }
}

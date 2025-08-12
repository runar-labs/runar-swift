import Foundation
@testable import RunarTransporter
import XCTest

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

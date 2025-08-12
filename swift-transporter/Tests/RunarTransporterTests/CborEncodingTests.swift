import Foundation
@testable import RunarTransporter
import SwiftCBOR
import XCTest

@available(macOS 12.0, iOS 15.0, *)
final class CborEncodingTests: XCTestCase {
    func testFramingAndCborEncodingOfNetworkMessage() throws {
        // Build a minimal message
        let msg = RunarNetworkMessage(
            sourceNodeId: "src",
            destinationNodeId: "dst",
            messageType: MessageTypes.REQUEST,
            payloads: [
                NetworkMessagePayloadItem(
                    path: "handshake",
                    valueBytes: Data([0x01, 0x02, 0x03]),
                    correlationId: "corr"
                ),
            ]
        )

        // Encode CBOR body
        let body = try CborMessageEncoder.encodeNetworkMessage(msg)

        // Frame: [4-byte BE length][CBOR bytes]
        var framed = Data()
        var len = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &len) { raw in
            framed.append(raw.bindMemory(to: UInt8.self))
        }
        framed.append(body)

        // Validate framing
        XCTAssertEqual(framed.count, 4 + body.count)
        // Extract length
        let parsedLen = framed.prefix(4).withUnsafeBytes { raw -> UInt32 in
            raw.load(as: UInt32.self).bigEndian
        }
        XCTAssertEqual(Int(parsedLen), body.count)

        // Validate CBOR content roughly matches schema
        let decodedOpt = try CBORDecoder(input: [UInt8](body)).decodeItem()
        guard let decoded = decodedOpt, case let CBOR.map(map) = decoded else {
            XCTFail("Expected top-level CBOR map"); return
        }
        func str(_ k: String) -> CBOR { .utf8String(k) }
        XCTAssertNotNil(map[str("source_node_id")])
        XCTAssertNotNil(map[str("destination_node_id")])
        XCTAssertNotNil(map[str("message_type")])
        XCTAssertNotNil(map[str("payloads")])

        if case let CBOR.array(items)? = map[str("payloads")] {
            XCTAssertEqual(items.count, 1)
            if case let CBOR.map(item)? = items.first {
                XCTAssertEqual(item[str("path")], CBOR.utf8String("handshake"))
                XCTAssertEqual(item[str("correlation_id")], CBOR.utf8String("corr"))
                if case let CBOR.byteString(bytes)? = item[str("value_bytes")] {
                    XCTAssertEqual(Data(bytes), Data([0x01, 0x02, 0x03]))
                } else {
                    XCTFail("value_bytes should be byteString")
                }
            } else { XCTFail("payload item should be map") }
        } else {
            XCTFail("payloads should be array")
        }
    }
}

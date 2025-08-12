@testable import RunarTransporter
import XCTest

final class TransporterIntegrationTests: XCTestCase {
    func testWireCodecRoundTripWithMappingAndFraming() throws {
        let msg = RunarNetworkMessage(
            sourceNodeId: "src",
            destinationNodeId: "dst",
            messageType: MessageTypes.REQUEST,
            payloads: [
                NetworkMessagePayloadItem(path: "/p", valueBytes: Data([0x10, 0x20]), correlationId: "c"),
            ]
        )
        let body = try TransportWireCodec.encodeBody(from: msg)
        let framed = Framing.encodeFrame(body)
        var buf = framed
        let frames = Framing.decodeFrames(&buf)
        XCTAssertEqual(frames.count, 1)
        let decoded = try TransportWireCodec.decodeBody(to: frames[0])
        XCTAssertEqual(decoded.sourceNodeId, "src")
        XCTAssertEqual(decoded.destinationNodeId, "dst")
        XCTAssertEqual(decoded.messageType, MessageTypes.REQUEST)
        XCTAssertEqual(decoded.payloads.first?.valueBytes, Data([0x10, 0x20]))
    }
}

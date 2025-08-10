import XCTest
@testable import RunarTransporter

@available(macOS 12.0, iOS 15.0, *)
final class BinaryEncoderDecoderTests: XCTestCase {
    func testDecodeNodeInfoRejectsUnreasonablePublicKeyLength() throws {
        // Build a minimal frame with an unreasonable key length (e.g., 0x00_01_86_A0 = 100_000)
        var data = Data()
        // key length = 100_000
        data.append(contentsOf: [0x00, 0x01, 0x86, 0xA0])
        // no further bytes; decode should throw
        XCTAssertThrowsError(try BinaryMessageEncoder.decodeNodeInfo(from: data)) { error in
            guard case let RunarTransportError.serializationError(msg) = error else {
                XCTFail("Unexpected error: \(error)"); return
            }
            XCTAssertTrue(msg.contains("Unreasonable node public key length"))
        }
    }

    func testDecodeNodeInfoRejectsInsufficientBytesForKey() throws {
        // key length = 4, but provide only 2 bytes
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x04])
        data.append(contentsOf: [0xAA, 0xBB])
        XCTAssertThrowsError(try BinaryMessageEncoder.decodeNodeInfo(from: data)) { error in
            guard case let RunarTransportError.serializationError(msg) = error else {
                XCTFail("Unexpected error: \(error)"); return
            }
            XCTAssertTrue(msg.contains("Insufficient data for public key"))
        }
    }

    func testEncodeDecodeNodeInfoRoundTrip() throws {
        let pk = Data(repeating: 0x42, count: 97)
        let node = RunarNodeInfo(
            nodePublicKey: pk,
            networkIds: ["it"],
            addresses: ["127.0.0.1:9999"],
            services: []
        )
        let encoded = try BinaryMessageEncoder.encodeNodeInfo(node)
        let decoded = try BinaryMessageEncoder.decodeNodeInfo(from: encoded)
        XCTAssertEqual(decoded.nodePublicKey, pk)
        XCTAssertEqual(decoded.networkIds, ["it"])
        XCTAssertEqual(decoded.addresses, ["127.0.0.1:9999"])
    }
}

@testable import RunarTransporter
import XCTest

final class FramingTests: XCTestCase {
    func testEncodeDecodeSingleFrame() {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        var framed = Framing.encodeFrame(payload)
        let frames = Framing.decodeFrames(&framed)
        XCTAssertEqual(frames, [payload])
        XCTAssertTrue(framed.isEmpty)
    }

    func testDecodeMultipleFramesWithPartialTail() {
        let p1 = Data([0x01])
        let p2 = Data([0x02, 0x03])
        let p3 = Data([0x04, 0x05, 0x06])
        var buf = Data()
        buf.append(Framing.encodeFrame(p1))
        buf.append(Framing.encodeFrame(p2))
        var tail = Framing.encodeFrame(p3)
        // Cut off last byte to simulate partial
        let cut = tail.removeLast()
        buf.append(tail)
        var mutable = buf
        let frames = Framing.decodeFrames(&mutable)
        XCTAssertEqual(frames, [p1, p2])
        // Remaining buffer should be partial frame (re-append cut makes it decodable)
        mutable.append(Data([cut]))
        let more = Framing.decodeFrames(&mutable)
        XCTAssertEqual(more, [p3])
        XCTAssertTrue(mutable.isEmpty)
    }

    func testInvalidLengthIsSkipped() {
        // Insert invalid zero-length
        var buf = Data([0, 0, 0, 0])
        let p = Data([0xAA])
        buf.append(Framing.encodeFrame(p))
        let frames = Framing.decodeFrames(&buf)
        XCTAssertEqual(frames, [p])
        XCTAssertTrue(buf.isEmpty)
    }
}

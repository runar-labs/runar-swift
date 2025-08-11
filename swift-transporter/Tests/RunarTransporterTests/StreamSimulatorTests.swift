import XCTest
@testable import RunarTransporter

final class StreamSimulatorTests: XCTestCase {
    func testRequestInnerLikeFlow() throws {
        // Handler echoes back uppercased payload
        let conn = SimulatedConnection(biResponseHandler: { req in
            let body = String(data: req, encoding: .utf8) ?? ""
            let resp = body.uppercased().data(using: .utf8)!
            return Framing.encodeFrame(resp)
        })
        var (send, recv) = conn.openBi()
        let requestPayload = Framing.encodeFrame("hello".data(using: .utf8)!)
        try send.writeAll(requestPayload)
        try send.finish()
        let resp = recv.readFrame()
        XCTAssertEqual(resp, "HELLO".data(using: .utf8)!)
    }

    func testPublishLikeFlow() throws {
        let conn = SimulatedConnection()
        let send = conn.openUni()
        try send.writeAll(Framing.encodeFrame(Data([0x01, 0x02])))
        try send.finish()
        // no response expected
    }
}



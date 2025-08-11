import XCTest
import Foundation
import SwiftCBOR
@testable import RunarTransporter

final class PayloadContextCborTests: XCTestCase {
    func testEncodePayloadWithOptionalContext() throws {
        let ctx = MessageContextSwift(profilePublicKey: Data([0x01, 0x02, 0x03]))
        let payload = PayloadWithContext(
            path: "/svc/act",
            valueBytes: Data([0xAA, 0xBB]),
            correlationId: "corr-1",
            context: ctx
        )
        let body = try CborMessageEncoder.encodePayloadWithContext(payload)
        let decodedOpt = try CBORDecoder(input: [UInt8](body)).decodeItem()
        guard let item = decodedOpt, case let CBOR.map(map) = item else { XCTFail("expected map"); return }
        func str(_ k: String) -> CBOR { .utf8String(k) }
        XCTAssertEqual(map[str("path")], CBOR.utf8String("/svc/act"))
        if case let CBOR.byteString(vb)? = map[str("value_bytes")] {
            XCTAssertEqual(Data(vb), Data([0xAA, 0xBB]))
        } else { XCTFail("value_bytes missing") }
        if case let CBOR.map(ctxMap)? = map[str("context")] {
            if case let CBOR.byteString(pk)? = ctxMap[str("profile_public_key")] {
                XCTAssertEqual(Data(pk), Data([0x01, 0x02, 0x03]))
            } else { XCTFail("profile_public_key missing") }
        } else { XCTFail("context missing") }
        XCTAssertEqual(map[str("correlation_id")], CBOR.utf8String("corr-1"))
    }

    func testEncodePayloadWithoutContext() throws {
        let payload = PayloadWithContext(
            path: "p",
            valueBytes: Data(),
            correlationId: "c",
            context: nil
        )
        let body = try CborMessageEncoder.encodePayloadWithContext(payload)
        let decodedOpt = try CBORDecoder(input: [UInt8](body)).decodeItem()
        guard let item = decodedOpt, case let CBOR.map(map) = item else { XCTFail("expected map"); return }
        XCTAssertNil(map[.utf8String("context")])
    }
}



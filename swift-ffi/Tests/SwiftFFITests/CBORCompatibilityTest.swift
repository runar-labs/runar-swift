import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI
import XCTest

final class CBORCompatibilityTest: XCTestCase {
    func testRevokeResponseCBORCompatibility() async throws {
        // Test the exact RevokeResponse structure that should work
        let revokeResponse = RevokeResponse(
            network_id: "test_network",
            ok: true
        )

        // Encode to CBOR using SwiftCBOR
        let encoder = CodableCBOREncoder()
        let cborData = try encoder.encode(revokeResponse)

        print("🔍 SwiftCBOR encoded RevokeResponse: \(cborData.map { String(format: "%02x", $0) }.joined())")
        print("🔍 SwiftCBOR encoded length: \(cborData.count) bytes")

        // Decode back using SwiftCBOR
        let decoder = CodableCBORDecoder()
        let decodedResponse = try decoder.decode(RevokeResponse.self, from: cborData)

        XCTAssertEqual(decodedResponse.network_id, "test_network")
        XCTAssertTrue(decodedResponse.ok)

        print("✅ SwiftCBOR round-trip test passed")
    }

    func testRevokeResponseWithKnownCBOR() async throws {
        // First, let's see what SwiftCBOR actually produces for this structure
        let revokeResponse = RevokeResponse(
            network_id: "test_network",
            ok: true
        )

        let encoder = CodableCBOREncoder()
        let cborData = try encoder.encode(revokeResponse)

        print("🔍 SwiftCBOR produces: \(cborData.map { String(format: "%02x", $0) }.joined())")
        print("🔍 SwiftCBOR length: \(cborData.count) bytes")

        // Now try to decode it back
        let decoder = CodableCBORDecoder()
        let decodedResponse = try decoder.decode(RevokeResponse.self, from: cborData)

        XCTAssertEqual(decodedResponse.network_id, "test_network")
        XCTAssertTrue(decodedResponse.ok)

        print("✅ SwiftCBOR round-trip with known data passed")
    }
}

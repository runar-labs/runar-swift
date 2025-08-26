@testable import RunarFFI
import XCTest

final class AgreementKeyTest: XCTestCase {
    func testGetAgreementPublicKey() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test that we can get the agreement public key directly
        let publicKey = try keys.nodeGetAgreementPublicKey()

        // Should return non-empty data
        XCTAssertFalse(publicKey.isEmpty, "Agreement public key should not be empty")

        // Should be a reasonable size for a public key (typically 65 bytes for secp256r1)
        XCTAssertGreaterThan(publicKey.count, 32, "Agreement public key should be at least 32 bytes")
        XCTAssertLessThan(publicKey.count, 256, "Agreement public key should be less than 256 bytes")

        print("✅ Agreement public key retrieved successfully: \(publicKey.count) bytes")
    }
}

import XCTest
import Security
@testable import RunarKeys

final class NodeIdentitySigningTests: XCTestCase {
    func testGenerateAndSign() throws {
        let label = "com.runar.keys.test.identity.\(UUID().uuidString)"
        let key: SecKey
        do {
            key = try NodeIdentitySigning.generateOrLoad(label: label)
        } catch {
            throw XCTSkip("Secure Enclave not available in this test environment: \(error)")
        }
        // Inspect attributes to see if key is in Secure Enclave
        guard let attrs = SecKeyCopyAttributes(key) as? [CFString: Any] else {
            return XCTFail("No attributes")
        }
        let tokenId = attrs[kSecAttrTokenID] as? String
        let isSE = (tokenId == (kSecAttrTokenIDSecureEnclave as String))
        var err: Unmanaged<CFError>?
        let privExport = SecKeyCopyExternalRepresentation(key, &err)
        if isSE {
            XCTAssertNil(privExport, "SE private key should be non-extractable")
        }

        let message = Data("node-identity-sign".utf8)
        let sig = try NodeIdentitySigning.sign(data: message, with: key)
        XCTAssertFalse(sig.isEmpty)

        // Export public key x963 and verify basic shape
        let pubX963 = try NodeIdentitySigning.publicKeyX963(from: key)
        XCTAssertEqual(pubX963.first, 0x04)
    }
}



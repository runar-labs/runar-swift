import XCTest
@testable import RunarKeys
import X509

final class CSRBuilderTests: XCTestCase {
    func testBuildCSRAndParse() throws {
        let label = "com.runar.keys.test.identity.\(UUID().uuidString)"
        let key: SecKey
        do { key = try NodeIdentitySigning.generateOrLoad(label: label) } catch { throw XCTSkip("SE unavailable: \(error)") }
        let cn = "node-csr-test"
        let der = try CSRBuilder.buildCSRMessageSignedManual(subjectCN: cn, signingKey: key, nodeIdSAN: "node.test")
        let parsed = try CertificateSigningRequest(derEncoded: Array(der))
        XCTAssertTrue(parsed.subject.description.contains("CN=\(cn)"))
    }

    func testBuildCSRWithSoftwareSecKey() throws {
        // Generate software P-256 key (no Secure Enclave)
        let params: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false,
        ]
        var err: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(params as CFDictionary, &err) else {
            throw XCTSkip("Cannot create software SecKey: \(err?.takeRetainedValue().localizedDescription ?? "unknown")")
        }
        let der = try CSRBuilder.buildCSRMessageSignedManual(subjectCN: "software-csr-test", signingKey: priv, nodeIdSAN: "node.test")
        let parsed = try CertificateSigningRequest(derEncoded: Array(der))
        XCTAssertTrue(parsed.subject.description.contains("software-csr-test"))
    }
}



import XCTest
import X509
@testable import RunarKeys

final class CertificateTests: XCTestCase {
    func testSerialNumberStoreMonotonic() throws {
        let a = try SerialNumberStore.nextSerialUInt64()
        let b = try SerialNumberStore.nextSerialUInt64()
        XCTAssertGreaterThan(b, a)
        let be = try SerialNumberStore.nextSerialBytesBigEndian()
        XCTAssertEqual(be.count, 8)
    }

    func testCSRPoPVerificationAndIssuance() throws {
        let ca = try CertificateAuthority.createCA(subjectCN: "Runar Test CA")

        // Software P-256 SecKey for unit test
        let params: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false,
        ]
        var err: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(params as CFDictionary, &err) else {
            throw XCTSkip("Cannot create software SecKey: \(err?.takeRetainedValue().localizedDescription ?? "unknown")")
        }

        let csrDER = try CSRBuilder.buildCSRMessageSignedManual(subjectCN: "node-csr-test", signingKey: priv, nodeIdSAN: "node.test")
        let csr = try CertificateSigningRequest(derEncoded: Array(csrDER))
        XCTAssertTrue(csr.publicKey.isValidSignature(csr.signature, for: csr))

        let leaf = try CertificateIssuer.signLeafWithCSR(
            ca: ca,
            csr: csr,
            subjectOverrideCN: "node-leaf",
            sanDNS: ["node.test"],
            validityDays: 30
        )

        XCTAssertTrue(leaf.subject.description.contains("node-leaf"))
        try CertificateValidator.validateChain(leaf: leaf, ca: ca.certificate, sniHost: "node.test")

        let spki = CertificateUtils.spkiBytes(leaf.publicKey)
        XCTAssertTrue(CertificateUtils.isSPKIPinned(leaf, pinnedSPKI: spki))
    }
}



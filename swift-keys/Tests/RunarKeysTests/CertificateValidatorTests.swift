import XCTest
@testable import RunarKeys
import X509

final class CertificateValidatorTests: XCTestCase {
    func testValidateChain() throws {
        let ca = try CertificateAuthority.createCA(subjectCN: "Runar Test CA")
        // Build CSR via software key
        let params: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false,
        ]
        var err: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(params as CFDictionary, &err) else {
            throw XCTSkip("Cannot create software SecKey: \(err?.takeRetainedValue().localizedDescription ?? "unknown")")
        }
        let csrDER = try CSRBuilder.buildCSRMessageSignedManual(subjectCN: "node-1", signingKey: priv, nodeIdSAN: "node-1")
        let csr = try CertificateSigningRequest(derEncoded: Array(csrDER))
        XCTAssertTrue(csr.publicKey.isValidSignature(csr.signature, for: csr))

        let leaf = try CertificateIssuer.signLeafWithCSR(ca: ca, csr: csr, subjectOverrideCN: "node-1", sanDNS: ["node-1"], validityDays: 90)
        try CertificateValidator.validateChain(leaf: leaf, ca: ca.certificate, sniHost: "node-1")
    }
}



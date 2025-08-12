import RunarKeys
import Security
import SwiftCommon
import XCTest

final class TrustEvaluationTests: XCTestCase {
    func testSecTrustEvaluationWithRunarCA() throws {
        let caKM = try MobileKeyManager(logger: ConsoleLogger(prefix: "CA"))
        _ = try caKM.initializeUserRootKey()
        try caKM.createCACertificate()
        let caCert = caKM.getCaCertificate()

        let nodeKM = try MobileKeyManager(logger: ConsoleLogger(prefix: "N"))
        _ = try nodeKM.initializeUserRootKey()
        let st = try nodeKM.generateCSR()
        let issued = try caKM.processSetupToken(st)
        try nodeKM.installCertificate(issued)
        let leafCert = issued.nodeCertificate

        guard let secLeaf = SecCertificateCreateWithData(nil, leafCert.toDER() as CFData) else { XCTFail("leaf to SecCertificate"); return }
        guard let secCA = SecCertificateCreateWithData(nil, caCert.toDER() as CFData) else { XCTFail("ca to SecCertificate"); return }

        // SSL policy for server certificate with hostname
        let policy = SecPolicyCreateSSL(true, "localhost" as CFString)
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(secLeaf, policy, &trust)
        XCTAssertEqual(status, errSecSuccess)
        guard let t = trust else { XCTFail("no trust"); return }

        // Provide intermediate/chain if needed (here: just CA)
        let anchors = [secCA] as CFArray
        XCTAssertEqual(SecTrustSetAnchorCertificates(t, anchors), errSecSuccess)
        // Evaluate with anchors-only true (strict private CA)
        _ = SecTrustSetAnchorCertificatesOnly(t, true)

        var error: CFError?
        let ok = SecTrustEvaluateWithError(t, &error)
        if !ok {
            XCTFail("SecTrust failed: \(String(describing: error))")
        }
    }
}

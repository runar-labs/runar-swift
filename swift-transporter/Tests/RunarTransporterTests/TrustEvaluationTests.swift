import RunarKeys
import Security
import SwiftCommon
import XCTest

final class TrustEvaluationTests: XCTestCase {
    func testSecTrustEvaluationWithRunarCA() throws {
        let km = RunarKeys.MobileKeyManager()
        let ca = try km.createCA(subjectCN: "Runar Test CA")
        let caCert = ca.generated.certificate

        let nodeSec = try km.generateNodeIdentity(label: "node-\(UUID().uuidString)")
        let nodePub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: nodeSec)
        let nodeId = RunarKeys.Ids.compactId(nodePub)
        let csr = try km.buildCSR(signingKey: nodeSec, subjectCN: nodeId, nodeIdSAN: nodeId)
        let leafCert = try km.issueLeaf(from: ca, csrDER: csr, subjectOverrideCN: nodeId, sanDNS: [nodeId], validityDays: 180)

        guard let secLeaf = SecCertificateCreateWithData(nil, RunarKeys.CertificateUtils.toDER(leafCert) as CFData) else { XCTFail("leaf to SecCertificate"); return }
        guard let secCA = SecCertificateCreateWithData(nil, RunarKeys.CertificateUtils.toDER(caCert) as CFData) else { XCTFail("ca to SecCertificate"); return }

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

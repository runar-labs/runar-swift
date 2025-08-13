import Foundation
import Security
import X509

enum CertificateValidator {
    static func validateChain(leaf: Certificate, ca: Certificate, sniHost: String? = nil) throws {
        guard let secLeaf = CertificateUtils.toSecCertificate(leaf), let secCA = CertificateUtils.toSecCertificate(ca) else {
            throw NSError(domain: "Cert", code: -1, userInfo: [NSLocalizedDescriptionKey: "SecCertificate conversion failed"])
        }
        let policy = SecPolicyCreateSSL(true, sniHost as CFString?)
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates([secLeaf, secCA] as CFArray, policy, &trust) == errSecSuccess, let t = trust else {
            throw NSError(domain: "Cert", code: -1, userInfo: [NSLocalizedDescriptionKey: "SecTrust create failed"])
        }
        guard SecTrustSetAnchorCertificates(t, [secCA] as CFArray) == errSecSuccess else {
            throw NSError(domain: "Cert", code: -1, userInfo: [NSLocalizedDescriptionKey: "Set anchor failed"])
        }
        var err: CFError?
        guard SecTrustEvaluateWithError(t, &err) else {
            throw err ?? NSError(domain: "Cert", code: -1)
        }
    }
}



import Foundation
import Security
import CryptoKit
import X509

public struct MobileKeyManager {
    public struct CAHandle {
        public let generated: CertificateAuthority.GeneratedCA
    }

    public init() {}

    // User root
    public func initializeUserRoot(secret: Data, requireUserPresence: Bool = false, requireBiometryCurrentSet: Bool = false) throws {
        try UserRootStore.save(secret, requireUserPresence: requireUserPresence, requireBiometryCurrentSet: requireBiometryCurrentSet)
    }

    public func loadUserRoot() throws -> Data {
        try UserRootStore.load()
    }

    // Profile/network keys
    public func deriveProfileAgreement(label: String, userRoot: Data) throws -> P256.KeyAgreement.PrivateKey {
        try ProfileKeys.deriveAgreementPrivateKey(userRoot: userRoot, label: label)
    }

    public func deriveNetworkAgreement(label: String, userRoot: Data) throws -> P256.KeyAgreement.PrivateKey {
        try NetworkKeys.deriveAgreementPrivateKey(userRoot: userRoot, label: label)
    }

    public func exportNetworkAgreementWrapped(_ networkPriv: P256.KeyAgreement.PrivateKey, to nodePub: P256.KeyAgreement.PublicKey) throws -> Data {
        try NetworkKeys.exportWrappedPrivateScalar(networkPriv, to: nodePub)
    }

    public func importNetworkAgreementWrapped(_ wrapped: Data, for nodePriv: P256.KeyAgreement.PrivateKey) throws -> P256.KeyAgreement.PrivateKey {
        try NetworkKeys.importWrappedPrivateScalar(wrapped, for: nodePriv)
    }

    // Node identity (SE)
    public func generateNodeIdentity(label: String) throws -> SecKey {
        try NodeIdentitySigning.generateOrLoad(label: label)
    }

    // CSR
    public func buildCSR(signingKey: SecKey, subjectCN: String, nodeIdSAN: String?) throws -> Data {
        try CSRBuilder.buildCSRMessageSignedManual(subjectCN: subjectCN, signingKey: signingKey, nodeIdSAN: nodeIdSAN)
    }

    // CA & issuance
    public func createCA(subjectCN: String, validityYears: Int = 10) throws -> CAHandle {
        return CAHandle(generated: try CertificateAuthority.createCA(subjectCN: subjectCN, validityYears: validityYears))
    }

    public func issueLeaf(from ca: CAHandle, csrDER: Data, subjectOverrideCN: String?, sanDNS: [String], validityDays: Int) throws -> Certificate {
        let req = try CertificateSigningRequest(derEncoded: Array(csrDER))
        // Ensure serial number is minimally-encoded positive INTEGER
        return try CertificateIssuer.signLeafWithCSR(ca: ca.generated, csr: req, subjectOverrideCN: subjectOverrideCN, sanDNS: sanDNS, validityDays: validityDays)
    }

    // Validation & pinning
    public func validateChain(leaf: Certificate, ca: Certificate, sniHost: String?) throws {
        try CertificateValidator.validateChain(leaf: leaf, ca: ca, sniHost: sniHost)
    }

    public func spkiPinned(_ cert: Certificate, expectedSPKI: Data) -> Bool {
        CertificateUtils.isSPKIPinned(cert, pinnedSPKI: expectedSPKI)
    }
}



import XCTest
import CryptoKit
import X509
@testable import RunarKeys

final class EndToEndTests: XCTestCase {
    func test_full_flow() throws {
        // 1) Mobile: user-root (in-memory for test)
        let userRoot = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // 2) Derive profile and network agreement keys
        let profilePriv = try ProfileKeys.deriveAgreementPrivateKey(userRoot: userRoot, label: "personal")
        let networkPriv = try NetworkKeys.deriveAgreementPrivateKey(userRoot: userRoot, label: "default")

        // 3) Node identity signing key (software SecKey for test)
        let params: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false,
        ]
        var sErr: Unmanaged<CFError>?
        guard let nodeSigning = SecKeyCreateRandomKey(params as CFDictionary, &sErr) else {
            throw XCTSkip("Cannot create software SecKey: \(sErr?.takeRetainedValue().localizedDescription ?? "unknown")")
        }

        // 4) Build CSR (message-signed), SAN=node-id
        let nodeId = Ids.compactId(try NodeIdentitySigning.publicKeyX963(from: nodeSigning))
        let csrDER = try CSRBuilder.buildCSRMessageSignedManual(subjectCN: "node-csr-test", signingKey: nodeSigning, nodeIdSAN: nodeId)
        let csr = try CertificateSigningRequest(derEncoded: Array(csrDER))
        XCTAssertTrue(csr.publicKey.isValidSignature(csr.signature, for: csr))

        // 5) CA and leaf issuance using CSR (monotonic serials inside)
        let ca = try CertificateAuthority.createCA(subjectCN: "Runar Test CA", validityYears: 3)
        let leaf = try CertificateIssuer.signLeafWithCSR(ca: ca, csr: csr, subjectOverrideCN: "node-leaf", sanDNS: [nodeId], validityDays: 90)

        // 6) Chain validation with SNI and SPKI pinning
        try CertificateValidator.validateChain(leaf: leaf, ca: ca.certificate, sniHost: nodeId)
        let spki = CertificateUtils.spkiBytes(leaf.publicKey)
        XCTAssertTrue(CertificateUtils.isSPKIPinned(leaf, pinnedSPKI: spki))

        // 7) Network key export/import (wrap to node, unwrap at node)
        let nodeNetPriv = P256.KeyAgreement.PrivateKey()
        let nodeNetPub = nodeNetPriv.publicKey
        let wrappedScalar = try NetworkKeys.exportWrappedPrivateScalar(networkPriv, to: nodeNetPub)
        let importedNetwork = try NetworkKeys.importWrappedPrivateScalar(wrappedScalar, for: nodeNetPriv)
        XCTAssertEqual(importedNetwork.publicKey.rawRepresentation, networkPriv.publicKey.rawRepresentation)

        // 8) Multi-recipient envelope (profile + node network)
        let message = Data("hello e2e".utf8)
        let env = try MultiRecipientEnvelope.encrypt(data: message, recipients: [
            "profile": profilePriv.publicKey,
            "network": importedNetwork.publicKey,
        ])
        let nodePT = try MultiRecipientEnvelope.decrypt(env, recipientLabel: "network", recipientPrivateKey: importedNetwork)
        XCTAssertEqual(nodePT, message)
        let mobilePT = try MultiRecipientEnvelope.decrypt(env, recipientLabel: "profile", recipientPrivateKey: profilePriv)
        XCTAssertEqual(mobilePT, message)
    }
}



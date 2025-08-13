import Foundation
import CryptoKit
import X509
import SwiftASN1

public struct CertificateIssuer {
    public static func signLeaf(
        ca: CertificateAuthority.GeneratedCA,
        subjectCN: String,
        sanDNS: [String],
        validityDays: Int,
        serialBytes: [UInt8]
    ) throws -> Certificate {
        let notBefore = Date().addingTimeInterval(-60)
        let notAfter = Date().addingTimeInterval(TimeInterval(validityDays * 24 * 60 * 60))
        let subject = try distinguishedName(cn: subjectCN)

        // Leaf public key will be provided as SPKI; for demo, use CA pub (caller should pass leaf pub in real impl)
        let leafKey = P256.Signing.PrivateKey()
        let leafPub = try Certificate.PublicKey(P256.Signing.PublicKey(x963Representation: leafKey.publicKey.x963Representation))

        let ski = ArraySlice(Data(SHA256.hash(data: leafKey.publicKey.x963Representation)))
        let aki = ArraySlice(Data(SHA256.hash(data: ca.privateKey.publicKey.x963Representation)))

        let san = SubjectAlternativeNames(sanDNS.map { GeneralName.dnsName($0) })

        let exts = try Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(digitalSignature: true))
            try Critical(ExtendedKeyUsage([.serverAuth, .clientAuth]))
            SubjectKeyIdentifier(keyIdentifier: ski)
            AuthorityKeyIdentifier(keyIdentifier: aki)
            san
        }

        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(bytes: ArraySlice(serialBytes)),
            publicKey: leafPub,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: ca.certificate.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: exts,
            issuerPrivateKey: Certificate.PrivateKey(ca.privateKey)
        )
        return cert
    }

    private static func distinguishedName(cn: String) throws -> DistinguishedName {
        let attr = try RelativeDistinguishedName.Attribute(type: .RDNAttributeType.commonName, printableString: cn)
        return DistinguishedName([RelativeDistinguishedName([attr])])
    }
}



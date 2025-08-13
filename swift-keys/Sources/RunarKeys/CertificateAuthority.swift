import Foundation
import CryptoKit
import X509
import SwiftASN1

struct CertificateAuthority {
    struct GeneratedCA {
        let privateKey: P256.Signing.PrivateKey
        let certificate: Certificate
    }

    static func createCA(subjectCN: String, validityYears: Int = 10) throws -> GeneratedCA {
        let key = P256.Signing.PrivateKey()
        let subject = try distinguishedName(cn: subjectCN)
        let notBefore = Date().addingTimeInterval(-60)
        let notAfter = Date().addingTimeInterval(TimeInterval(validityYears * 365 * 24 * 60 * 60))
        let pub = try Certificate.PublicKey(P256.Signing.PublicKey(x963Representation: key.publicKey.x963Representation))
        let ski = ArraySlice(Data(SHA256.hash(data: key.publicKey.x963Representation)))

        let exts = try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
            Critical(KeyUsage(keyCertSign: true, cRLSign: true))
            SubjectKeyIdentifier(keyIdentifier: ski)
            AuthorityKeyIdentifier(keyIdentifier: ski)
        }

        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: pub,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: exts,
            issuerPrivateKey: Certificate.PrivateKey(key)
        )

        return .init(privateKey: key, certificate: cert)
    }

    private static func distinguishedName(cn: String) throws -> DistinguishedName {
        let attr = try RelativeDistinguishedName.Attribute(type: .RDNAttributeType.commonName, printableString: cn)
        return DistinguishedName([RelativeDistinguishedName([attr])])
    }
}



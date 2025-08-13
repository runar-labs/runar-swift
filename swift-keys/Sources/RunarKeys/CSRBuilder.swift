import Foundation
import Security
import CryptoKit
import X509
import SwiftASN1

public struct CSRBuilder {
    public static func buildCSR(subjectCN: String, signingKey: SecKey) throws -> Data {
        let subject = try distinguishedName(cn: subjectCN)

        // Build Certificate.PublicKey from SecKey public x963
        guard let pub = SecKeyCopyPublicKey(signingKey) else { throw NSError(domain: "CSR", code: -1) }
        var perr: Unmanaged<CFError>?
        guard let pubX963 = SecKeyCopyExternalRepresentation(pub, &perr) as Data? else {
            throw NSError(domain: "CSR", code: -1, userInfo: [NSLocalizedDescriptionKey: perr?.takeRetainedValue().localizedDescription ?? "pub export failed"])
        }
        let p256Pub = try P256.Signing.PublicKey(x963Representation: pubX963)
        let certPub = try Certificate.PublicKey(p256Pub)

        // Build CSR using our fork's external-signing initializer (signatureDER = X9.62 ECDSA DER)
        let criBytes = try CertificateSigningRequestHelper.infoBytes(version: .v1, subject: subject, publicKey: certPub, attributes: .init())
        let digest = Data(SHA256.hash(data: Data(criBytes)))
        var serr: Unmanaged<CFError>?
        guard let sigDER = SecKeyCreateSignature(signingKey, SecKeyAlgorithm.ecdsaSignatureDigestX962SHA256, digest as CFData, &serr) as Data? else {
            throw NSError(domain: "CSR", code: -1, userInfo: [NSLocalizedDescriptionKey: serr?.takeRetainedValue().localizedDescription ?? "sign failed"])
        }
        let csr = try CertificateSigningRequest(
            version: .v1,
            subject: subject,
            publicKey: certPub,
            attributes: .init(),
            signatureAlgorithm: .ecdsaWithSHA256,
            signatureDER: Array(sigDER)
        )
        return try Data(CertificateSigningRequestHelper.derEncoded(csr))
    }

    private static func distinguishedName(cn: String) throws -> DistinguishedName {
        let attr = try RelativeDistinguishedName.Attribute(type: .RDNAttributeType.commonName, printableString: cn)
        return DistinguishedName([RelativeDistinguishedName([attr])])
    }
}



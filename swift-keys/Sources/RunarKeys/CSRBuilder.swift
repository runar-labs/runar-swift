import Foundation
import Security
import CryptoKit
import X509
import SwiftASN1

struct CSRBuilder {
    static func buildCSR(subjectCN: String, signingKey: SecKey) throws -> Data {
        let subject = try distinguishedName(cn: subjectCN)

        // Build Certificate.PublicKey from SecKey public x963
        guard let pub = SecKeyCopyPublicKey(signingKey) else { throw NSError(domain: "CSR", code: -1) }
        var perr: Unmanaged<CFError>?
        guard let pubX963 = SecKeyCopyExternalRepresentation(pub, &perr) as Data? else {
            throw NSError(domain: "CSR", code: -1, userInfo: [NSLocalizedDescriptionKey: perr?.takeRetainedValue().localizedDescription ?? "pub export failed"])
        }
        let p256Pub = try P256.Signing.PublicKey(x963Representation: pubX963)
        let certPub = try Certificate.PublicKey(p256Pub)

        // Build CRI
        let info = CertificationRequestInfo(
            subject: subject,
            publicKey: certPub,
            attributes: .init()
        )

        // DER encode CRI and sign digest via SecKey
        var s = DER.Serializer()
        try info.serialize(into: &s)
        let criDER = Data(s.serializedBytes)
        let digest = Data(SHA256.hash(data: criDER))
        var serr: Unmanaged<CFError>?
        guard let sigDER = SecKeyCreateSignature(signingKey, SecKeyAlgorithm.ecdsaSignatureDigestX962SHA256, digest as CFData, &serr) as Data? else {
            throw NSError(domain: "CSR", code: -1, userInfo: [NSLocalizedDescriptionKey: serr?.takeRetainedValue().localizedDescription ?? "sign failed"])
        }

        // Assemble CSR
        let alg = AlgorithmIdentifier(algorithm: .ecdsaWithSHA256)
        let csr = CertificationRequest(info: info, algorithm: alg, signature: ArraySlice(sigDER))
        var out = DER.Serializer()
        try csr.serialize(into: &out)
        return Data(out.serializedBytes)
    }

    private static func distinguishedName(cn: String) throws -> DistinguishedName {
        let attr = try RelativeDistinguishedName.Attribute(type: .RDNAttributeType.commonName, printableString: cn)
        return DistinguishedName([RelativeDistinguishedName([attr])])
    }
}



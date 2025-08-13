import Foundation
import Security
import CryptoKit
import X509
import SwiftASN1

public struct CSRBuilder {
    public static func buildCSRMessageSigned(subjectCN: String, signingKey: SecKey) throws -> Data {
        try buildCSRMessageSignedManual(subjectCN: subjectCN, signingKey: signingKey)
    }

    public static func buildCSRDigestSigned(subjectCN: String, signingKey: SecKey) throws -> Data {
        try buildCSRDigestSignedManual(subjectCN: subjectCN, signingKey: signingKey)
    }

    public static func buildCSRMessageSignedManual(subjectCN: String, signingKey: SecKey, nodeIdSAN: String? = nil) throws -> Data {
        let subject = try distinguishedName(cn: subjectCN)
        guard let pub = SecKeyCopyPublicKey(signingKey) else { throw NSError(domain: "CSR", code: -1) }
        var perr: Unmanaged<CFError>?
        guard let pubX963 = SecKeyCopyExternalRepresentation(pub, &perr) as Data? else {
            throw NSError(domain: "CSR", code: -1, userInfo: [NSLocalizedDescriptionKey: perr?.takeRetainedValue().localizedDescription ?? "pub export failed"])
        }
        let p256Pub = try P256.Signing.PublicKey(x963Representation: pubX963)
        let certPub = try Certificate.PublicKey(p256Pub)

        let attributes = try buildExtensionRequestAttributes(nodeIdSAN: nodeIdSAN)
        let infoBytes = try CertificateSigningRequestHelper.infoBytes(version: .v1, subject: subject, publicKey: certPub, attributes: attributes)
        var serr: Unmanaged<CFError>?
        guard let sigDER = SecKeyCreateSignature(signingKey, SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256, Data(infoBytes) as CFData, &serr) as Data? else {
            throw NSError(domain: "CSR", code: -1, userInfo: [NSLocalizedDescriptionKey: serr?.takeRetainedValue().localizedDescription ?? "sign failed"])
        }
        let algIdBytes: [UInt8] = [0x30, 0x0A, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]
        let sigBitString = ASN1BitString(bytes: Array(sigDER)[...])

        var coder = DER.Serializer()
        try coder.appendConstructedNode(identifier: .sequence) { seq in
            // info
            seq.serializeRawBytes(infoBytes)
            // algorithm identifier (ecdsaWithSHA256)
            seq.serializeRawBytes(algIdBytes)
            // signature BIT STRING wrapping DER ECDSA signature
            try seq.serialize(sigBitString)
        }
        return Data(coder.serializedBytes)
    }

    public static func buildCSRDigestSignedManual(subjectCN: String, signingKey: SecKey, nodeIdSAN: String? = nil) throws -> Data {
        let subject = try distinguishedName(cn: subjectCN)
        guard let pub = SecKeyCopyPublicKey(signingKey) else { throw NSError(domain: "CSR", code: -1) }
        var perr: Unmanaged<CFError>?
        guard let pubX963 = SecKeyCopyExternalRepresentation(pub, &perr) as Data? else {
            throw NSError(domain: "CSR", code: -1, userInfo: [NSLocalizedDescriptionKey: perr?.takeRetainedValue().localizedDescription ?? "pub export failed"])
        }
        let p256Pub = try P256.Signing.PublicKey(x963Representation: pubX963)
        let certPub = try Certificate.PublicKey(p256Pub)

        let attributes = try buildExtensionRequestAttributes(nodeIdSAN: nodeIdSAN)
        let infoBytes = try CertificateSigningRequestHelper.infoBytes(version: .v1, subject: subject, publicKey: certPub, attributes: attributes)
        let digest = Data(SHA256.hash(data: Data(infoBytes)))
        var serr: Unmanaged<CFError>?
        guard let sigDER = SecKeyCreateSignature(signingKey, SecKeyAlgorithm.ecdsaSignatureDigestX962SHA256, digest as CFData, &serr) as Data? else {
            throw NSError(domain: "CSR", code: -1, userInfo: [NSLocalizedDescriptionKey: serr?.takeRetainedValue().localizedDescription ?? "sign failed"])
        }
        let algIdBytes: [UInt8] = [0x30, 0x0A, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]
        let sigBitString = ASN1BitString(bytes: Array(sigDER)[...])

        var coder = DER.Serializer()
        try coder.appendConstructedNode(identifier: .sequence) { seq in
            seq.serializeRawBytes(infoBytes)
            seq.serializeRawBytes(algIdBytes)
            try seq.serialize(sigBitString)
        }
        return Data(coder.serializedBytes)
    }

    public static func buildExtensionRequestAttributes(nodeIdSAN: String?) throws -> CertificateSigningRequest.Attributes {
        guard let nodeId = nodeIdSAN, !nodeId.isEmpty else { return .init() }
        let san = SubjectAlternativeNames([.dnsName(nodeId)])
        let exts = try Certificate.Extensions {
            san
        }
        let extReq = ExtensionRequest(extensions: exts)
        return try CertificateSigningRequest.Attributes([CertificateSigningRequest.Attribute(extReq)])
    }

    private static func distinguishedName(cn: String) throws -> DistinguishedName {
        let attr = try RelativeDistinguishedName.Attribute(type: .RDNAttributeType.commonName, printableString: cn)
        return DistinguishedName([RelativeDistinguishedName([attr])])
    }
}



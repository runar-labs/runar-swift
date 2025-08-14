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

        // Leaf public key will be provided as SPKI; for demo, generate a fresh key
        let leafKey = P256.Signing.PrivateKey()
        let leafPub = try Certificate.PublicKey(P256.Signing.PublicKey(x963Representation: leafKey.publicKey.x963Representation))

        // SKI/AKI as SHA-1 over SPKI DER bytes (RFC 5280)
        var leafSer = DER.Serializer()
        try leafPub.serialize(into: &leafSer)
        let leafSPKI = Data(leafSer.serializedBytes)
        let ski = ArraySlice(Data(Insecure.SHA1.hash(data: leafSPKI)))

        let caCertPub = try Certificate.PublicKey(P256.Signing.PublicKey(x963Representation: ca.privateKey.publicKey.x963Representation))
        var caSer = DER.Serializer()
        try caCertPub.serialize(into: &caSer)
        let caSPKI = Data(caSer.serializedBytes)
        let aki = ArraySlice(Data(Insecure.SHA1.hash(data: caSPKI)))

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

    public static func signLeafWithPublicKey(
        ca: CertificateAuthority.GeneratedCA,
        leafPublicKey: Certificate.PublicKey,
        subjectCN: String,
        sanDNS: [String],
        validityDays: Int,
        serialBytes: [UInt8]
    ) throws -> Certificate {
        let notBefore = Date().addingTimeInterval(-60)
        let notAfter = Date().addingTimeInterval(TimeInterval(validityDays * 24 * 60 * 60))
        let subject = try distinguishedName(cn: subjectCN)

        // Compute SKI/AKI (hash of SPKI DER bytes)
        var leafSer = DER.Serializer()
        try leafPublicKey.serialize(into: &leafSer)
        let leafSPKI = Data(leafSer.serializedBytes)
        let ski = ArraySlice(Data(Insecure.SHA1.hash(data: leafSPKI)))

        let caCertPub = try Certificate.PublicKey(P256.Signing.PublicKey(x963Representation: ca.privateKey.publicKey.x963Representation))
        var caSer = DER.Serializer()
        try caCertPub.serialize(into: &caSer)
        let caSPKI = Data(caSer.serializedBytes)
        let aki = ArraySlice(Data(Insecure.SHA1.hash(data: caSPKI)))

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
            publicKey: leafPublicKey,
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

    public static func signLeafWithCSR(
        ca: CertificateAuthority.GeneratedCA,
        csr: CertificateSigningRequest,
        subjectOverrideCN: String? = nil,
        sanDNS: [String],
        validityDays: Int
    ) throws -> Certificate {
        // Verify PoP: CSR signature over infoBytes with its public key
        let isValid = csr.publicKey.isValidSignature(csr.signature, for: csr)
        guard isValid else { throw NSError(domain: "Cert", code: -1, userInfo: [NSLocalizedDescriptionKey: "CSR PoP verification failed"]) }

        // Serial from monotonic store
        let serial = try SerialNumberStore.nextSerialBytesBigEndian()
        return try signLeafWithPublicKey(
            ca: ca,
            leafPublicKey: csr.publicKey,
            subjectCN: subjectOverrideCN ?? csr.subject.description,
            sanDNS: sanDNS,
            validityDays: validityDays,
            serialBytes: serial
        )
    }

    private static func distinguishedName(cn: String) throws -> DistinguishedName {
        let attr = try RelativeDistinguishedName.Attribute(type: .RDNAttributeType.commonName, utf8String: cn)
        return DistinguishedName([RelativeDistinguishedName([attr])])
    }
}



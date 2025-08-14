import Foundation
import Security
import X509
import SwiftASN1

public enum CertificateUtils {
    public static func toDER(_ cert: Certificate) -> Data {
        var s = DER.Serializer()
        try! cert.serialize(into: &s)
        return Data(s.serializedBytes)
    }

    public static func toSecCertificate(_ cert: Certificate) -> SecCertificate? {
        SecCertificateCreateWithData(nil, toDER(cert) as CFData)
    }

    public static func spkiBytes(_ pub: Certificate.PublicKey) -> Data {
        return Data(pub.subjectPublicKeyInfoBytes)
    }

    public static func isSPKIPinned(_ cert: Certificate, pinnedSPKI: Data) -> Bool {
        let actual = spkiBytes(cert.publicKey)
        return actual == pinnedSPKI
    }
}



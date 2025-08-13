import Foundation
import Security
import X509
import SwiftASN1

enum CertificateUtils {
    static func toDER(_ cert: Certificate) -> Data {
        var s = DER.Serializer()
        try! cert.serialize(into: &s)
        return Data(s.serializedBytes)
    }

    static func toSecCertificate(_ cert: Certificate) -> SecCertificate? {
        SecCertificateCreateWithData(nil, toDER(cert) as CFData)
    }
}



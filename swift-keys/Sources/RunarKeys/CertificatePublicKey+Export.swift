import Foundation
import X509

extension Certificate.PublicKey {
    func exportedPublicKeyBytes() throws -> Data {
        // Export SPKI then extract x963 from it via SubjectPublicKeyInfo
        var s = DER.Serializer()
        try self.serialize(into: &s)
        let spki = try SubjectPublicKeyInfo(derEncoded: s.serializedBytes)
        return Data(spki.subjectPublicKeyBytes)
    }
}



import Foundation
import X509
import SwiftASN1

extension Certificate.PublicKey {
    func serializedSPKI() throws -> Data {
        var serializer = DER.Serializer()
        try self.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }
}




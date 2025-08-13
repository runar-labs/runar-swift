import Foundation
import CryptoKit

public enum ProfileKeys {
    public static func deriveAgreementPrivateKey(userRoot: Data, label: String) throws -> P256.KeyAgreement.PrivateKey {
        var counter: UInt32 = 0
        while true {
            let scalar = try KeyDeriver.deriveScalar(master: userRoot, scope: "profile", purpose: "agreement", label: label, counterStart: counter)
            if let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: scalar) { return key }
            counter &+= 1
        }
    }
}



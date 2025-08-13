import Foundation
import CryptoKit

enum NetworkKeys {
    static func deriveAgreementPrivateKey(userRoot: Data, label: String) throws -> P256.KeyAgreement.PrivateKey {
        var counter: UInt32 = 0
        while true {
            let scalar = try KeyDeriver.deriveScalar(master: userRoot, scope: "network", purpose: "agreement", label: label, counterStart: counter)
            if let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: scalar) { return key }
            counter &+= 1
        }
    }

    static func exportWrappedPrivateScalar(_ priv: P256.KeyAgreement.PrivateKey, to nodePub: P256.KeyAgreement.PublicKey) throws -> Data {
        let scalar = priv.rawRepresentation
        return try ECIES.encrypt(data: scalar, recipientPublicKey: nodePub)
    }

    static func importWrappedPrivateScalar(_ wrapped: Data, for recipientPriv: P256.KeyAgreement.PrivateKey) throws -> P256.KeyAgreement.PrivateKey {
        let scalar = try ECIES.decrypt(encrypted: wrapped, recipientPrivateKey: recipientPriv)
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: scalar)
    }
}



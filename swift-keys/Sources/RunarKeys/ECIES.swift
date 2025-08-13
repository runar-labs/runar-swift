import Foundation
import CryptoKit

public struct ECIES {
    public static func encrypt(data: Data, recipientPublicKey: P256.KeyAgreement.PublicKey) throws -> Data {
        let ephPriv = P256.KeyAgreement.PrivateKey()
        let ephPub = ephPriv.publicKey
        let secret = try ephPriv.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let key = try deriveEnvelopeKey(secret: secret)
        let sealed = try AES.GCM.seal(data, using: key)
        let combined = sealed.combined ?? Data()
        return ephPub.x963Representation + combined
    }

    public static func decrypt(encrypted: Data, recipientPrivateKey: P256.KeyAgreement.PrivateKey) throws -> Data {
        precondition(encrypted.count > 65)
        let ephPubBytes = encrypted.prefix(65)
        let ct = encrypted.dropFirst(65)
        let ephPub = try P256.KeyAgreement.PublicKey(x963Representation: ephPubBytes)
        let secret = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephPub)
        let key = try deriveEnvelopeKey(secret: secret)
        let box = try AES.GCM.SealedBox(combined: ct)
        return try AES.GCM.open(box, using: key)
    }

    private static func deriveEnvelopeKey(secret: SharedSecret) throws -> SymmetricKey {
        let keyMaterial = secret.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                         salt: Data(),
                                                         sharedInfo: Data("runar-v1:ecies:envelope-key".utf8),
                                                         outputByteCount: 32)
        return keyMaterial
    }
}



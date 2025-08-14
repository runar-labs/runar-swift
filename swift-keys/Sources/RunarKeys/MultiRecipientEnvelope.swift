import Foundation
import CryptoKit

public struct MultiRecipientEnvelope {
    public let ciphertext: Data
    public let wraps: [String: Data] // label -> ECIES(wrapped symmetric key)

    public init(ciphertext: Data, wraps: [String: Data]) {
        self.ciphertext = ciphertext
        self.wraps = wraps
    }

    public static func encrypt(data: Data, recipients: [String: P256.KeyAgreement.PublicKey]) throws -> MultiRecipientEnvelope {
        let symmetricKey = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(data, using: symmetricKey)
        let combined = sealed.combined ?? Data()
        let keyBytes = symmetricKey.withUnsafeBytes { Data($0) }
        var wraps: [String: Data] = [:]
        for (label, pub) in recipients {
            wraps[label] = try ECIES.encrypt(data: keyBytes, recipientPublicKey: pub)
        }
        return MultiRecipientEnvelope(ciphertext: combined, wraps: wraps)
    }

    public static func decrypt(_ envelope: MultiRecipientEnvelope, recipientLabel: String, recipientPrivateKey: P256.KeyAgreement.PrivateKey) throws -> Data {
        guard let wrapped = envelope.wraps[recipientLabel] else {
            throw NSError(domain: "Envelope", code: -1, userInfo: [NSLocalizedDescriptionKey: "No wrap for label \(recipientLabel)"])
        }
        let keyBytes = try ECIES.decrypt(encrypted: wrapped, recipientPrivateKey: recipientPrivateKey)
        let symmetricKey = SymmetricKey(data: keyBytes)
        let box = try AES.GCM.SealedBox(combined: envelope.ciphertext)
        return try AES.GCM.open(box, using: symmetricKey)
    }
}



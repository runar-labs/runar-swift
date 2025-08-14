import Foundation
import CryptoKit

public enum NetworkKeys {
    public static func deriveAgreementPrivateKey(userRoot: Data, label: String) throws -> P256.KeyAgreement.PrivateKey {
        var counter: UInt32 = 0
        while true {
            let scalar = try KeyDeriver.deriveScalar(master: userRoot, scope: "network", purpose: "agreement", label: label, counterStart: counter)
            if let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: scalar) { return key }
            counter &+= 1
        }
    }

    public static func exportWrappedPrivateScalar(_ priv: P256.KeyAgreement.PrivateKey, to nodePub: P256.KeyAgreement.PublicKey) throws -> Data {
        let scalar = priv.rawRepresentation
        return try ECIES.encrypt(data: scalar, recipientPublicKey: nodePub)
    }

    public static func importWrappedPrivateScalar(_ wrapped: Data, for recipientPriv: P256.KeyAgreement.PrivateKey) throws -> P256.KeyAgreement.PrivateKey {
        let scalar = try ECIES.decrypt(encrypted: wrapped, recipientPrivateKey: recipientPriv)
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: scalar)
    }

    // Optional: encrypted at-rest storage for network private scalar (no plaintext persistence)
    public static func storeEncryptedScalar(label: String, scalarCiphertext: Data) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.runar.keys.network",
            kSecAttrAccount as String: label,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        var add = base
        add[kSecValueData as String] = scalarCiphertext
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let upd = SecItemUpdate(base as CFDictionary, [kSecValueData as String: scalarCiphertext] as CFDictionary)
            guard upd == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(upd)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public static func loadEncryptedScalar(label: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.runar.keys.network",
            kSecAttrAccount as String: label,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return data
    }
}



import Foundation
import Security
import CryptoKit

public struct NodeIdentitySigning {
    public static func generateOrLoad(label: String) throws -> SecKey {
        if let existing = findPrivateKey(label: label) { return existing }

        // Require Secure Enclave P-256 non-extractable key. No software fallback.
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: true,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: error?.takeRetainedValue().localizedDescription ?? "Key generation failed"])
        }
        return secKey
    }

    public static func sign(data: Data, with secKey: SecKey) throws -> Data {
        let alg = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(secKey, alg, data as CFData, &err) as Data? else {
            throw NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: err?.takeRetainedValue().localizedDescription ?? "Sign failed"])
        }
        return sig
    }

    public static func publicKeyX963(from secKey: SecKey) throws -> Data {
        guard let pub = SecKeyCopyPublicKey(secKey) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: "No public key"])
        }
        var err: Unmanaged<CFError>?
        guard let bytes = SecKeyCopyExternalRepresentation(pub, &err) as Data? else {
            throw NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: err?.takeRetainedValue().localizedDescription ?? "Pub export failed"])
        }
        return bytes
    }

    private static func findPrivateKey(label: String) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let k = (result as CFTypeRef?) {
            return (k as! SecKey)
        }
        return nil
    }
}



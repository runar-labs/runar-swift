import Foundation
import Security
import CryptoKit

enum RunarSEKeyManagerError: Error {
    case secureEnclaveUnavailable
    case keyGenerationFailed(OSStatus)
}

struct RunarSEKeyManager {
    static func createOrLoadP256SigningKey(label: String) throws -> SecKey {
        if let existing = findPrivateKey(label: label) { return existing }

        // Basic presence check by attempting to create with Secure Enclave token; will fail if unavailable

        let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], nil)!

        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: applicationTag(for: label),
                kSecAttrLabel as String: label,
                kSecAttrAccessControl as String: access,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            let osErr = (error?.takeRetainedValue() as? NSError)?.code ?? Int(errSecParam)
            throw RunarSEKeyManagerError.keyGenerationFailed(OSStatus(osErr))
        }
        return privateKey
    }

    private static func findPrivateKey(label: String) -> SecKey? {
        // Prefer application tag query
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: applicationTag(for: label),
            kSecReturnRef as String: true
        ]
        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess {
            // Fallback: label-based query
            query[kSecAttrApplicationTag as String] = nil
            query[kSecAttrLabel as String] = label
            status = SecItemCopyMatching(query as CFDictionary, &item)
        }
        guard status == errSecSuccess, let found = item, CFGetTypeID(found) == SecKeyGetTypeID() else { return nil }
        return (found as! SecKey)
    }

    private static func applicationTag(for label: String) -> Data {
        Data(label.utf8)
    }

    static func publicKeySHA256Hex(for privateKey: SecKey) -> String? {
        guard let pub = SecKeyCopyPublicKey(privateKey) else { return nil }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(pub, &error) as Data? else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func agreementPublicKey(from privateKey: SecKey) throws -> P256.KeyAgreement.PublicKey {
        guard let pub = SecKeyCopyPublicKey(privateKey) else { throw RunarSEKeyManagerError.keyGenerationFailed(errSecInvalidKeyRef) }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(pub, &error) as Data? else { throw RunarSEKeyManagerError.keyGenerationFailed(errSecParam) }
        return try P256.KeyAgreement.PublicKey(x963Representation: data)
    }
}



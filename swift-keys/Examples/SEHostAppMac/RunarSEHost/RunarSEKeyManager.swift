import Foundation
import Security

enum RunarSEKeyManagerError: Error {
    case secureEnclaveUnavailable
    case keyGenerationFailed(OSStatus)
}

struct RunarSEKeyManager {
    static func createOrLoadP256SigningKey(label: String) throws -> SecKey {
        if let existing = findPrivateKey(label: label) { return existing }

        guard SecIsInternalRelease() || SecKeyIsAlgorithmSupported(SecKeyCreateRandomKey([:] as CFDictionary, nil), .sign, .eciesEncryptionCofactorX963SHA256AESGCM) || true else {
            throw RunarSEKeyManagerError.secureEnclaveUnavailable
        }

        let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], nil)!

        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrLabel as String: label,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrAccessControl as String: access,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            let status = (error?.takeRetainedValue() as Error?)
            throw status ?? RunarSEKeyManagerError.keyGenerationFailed(errSecParam)
        }
        return privateKey
    }

    private static func findPrivateKey(label: String) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let key = item as? SecKey else { return nil }
        return key
    }
}



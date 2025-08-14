import Foundation
import Security

public enum UserRootStore {
    static let service = "com.runar.keys.user-root"
    static let account = "root"

    public static func save(_ secret: Data) throws {
        try save(secret, requireUserPresence: false, requireBiometryCurrentSet: false)
    }

    public static func save(_ secret: Data, requireUserPresence: Bool, requireBiometryCurrentSet: Bool) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = secret
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        var flags: SecAccessControlCreateFlags = []
        if requireUserPresence { flags.insert(.userPresence) }
        if requireBiometryCurrentSet { flags.insert(.biometryCurrentSet) }
        if let ac = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, nil) {
            addQuery[kSecAttrAccessControl as String] = ac
        }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attrsToUpdate: [String: Any] = [
                kSecValueData as String: secret,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            ]
            let upd = SecItemUpdate(baseQuery as CFDictionary, attrsToUpdate as CFDictionary)
            guard upd == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(upd)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public static func load() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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



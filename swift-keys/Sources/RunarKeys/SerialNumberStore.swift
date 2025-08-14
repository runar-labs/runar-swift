import Foundation
import Security

public enum SerialNumberStore {
    private static let service = "com.runar.keys.serials"
    private static let account = "leaf-serial"

    public static func nextSerialUInt64() throws -> UInt64 {
        let current = try load() ?? 0
        let next = current &+ 1
        try save(next)
        return next
    }

    public static func nextSerialBytesBigEndian() throws -> [UInt8] {
        let value = try nextSerialUInt64()
        var be = value.bigEndian
        return withUnsafeBytes(of: &be) { Array($0) }
    }

    private static func save(_ value: UInt64) throws {
        var v = value.bigEndian
        let data = withUnsafeBytes(of: &v) { Data($0) }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let upd = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
            guard upd == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(upd)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func load() throws -> UInt64? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 8 else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let value = data.withUnsafeBytes { ptr -> UInt64 in
            ptr.load(as: UInt64.self).bigEndian
        }
        return value
    }
}



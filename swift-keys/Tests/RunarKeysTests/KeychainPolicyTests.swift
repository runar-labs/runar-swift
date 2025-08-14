import XCTest
@testable import RunarKeys
import Security

final class KeychainPolicyTests: XCTestCase {
    func testUserRootStoreAttributes() throws {
        let secret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        // Skip on CI environments that disallow keychain attr readback
        do { try UserRootStore.save(secret) } catch {
            throw XCTSkip("Keychain not available in this environment: \(error)")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.runar.keys.user-root",
            kSecAttrAccount as String: "root",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess)
        let attrs = result as? [String: Any]
        XCTAssertNotNil(attrs)
        let accessible = attrs?[kSecAttrAccessible as String] as? String
        XCTAssertEqual(accessible, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        // synchronizable may come back as kCFBooleanFalse or 0; accept either falsey
        let syncAny = attrs?[kSecAttrSynchronizable as String]
        if let b = syncAny as? Bool { XCTAssertEqual(b, false) }
        if let n = syncAny as? NSNumber { XCTAssertEqual(n.intValue, 0) }
    }

    func testNetworkEncryptedBlobStoreLoad() throws {
        let label = "net-enc-\(UUID().uuidString)"
        let blob = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
        try NetworkKeys.storeEncryptedScalar(label: label, scalarCiphertext: blob)
        let loaded = try NetworkKeys.loadEncryptedScalar(label: label)
        XCTAssertEqual(loaded, blob)
    }
}



import RunarFFI
@testable import RunarSerializer
import RunarSerializerMacros
import SwiftCBOR
import XCTest

final class EncryptedMacroTest: XCTestCase {
    func testBasicEncryptionDecryption() async throws {
        // Test basic encryption/decryption without macro
        struct TestUser: Codable {
            let id: Int
            let name: String
        }

        let user = TestUser(id: 123, name: "John")

        // Serialize to JSON
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(user)

        // Use real keystore
        // Use FFI-backed keystore via FFIKeyStore. Initialize root key for profile encryption
        let keys = try FFIKeys()
        try keys.mobileInitializeUserRootKey()
        let keystore = FFIKeyStore(keys: keys)

        // Encrypt with envelope encryption (profile-only)
        let profileId = "test-profile"
        let envelopeData = try keystore.encryptWithEnvelope(
            data: jsonData,
            networkId: nil,
            profileIds: [profileId]
        )

        // Decrypt using profile key
        let decryptedData = try keystore.decryptWithProfile(envelopeData: envelopeData, profileId: profileId)

        // Decode JSON
        let decoder = JSONDecoder()
        let decodedUser = try decoder.decode(TestUser.self, from: decryptedData)

        XCTAssertEqual(decodedUser.id, user.id)
        XCTAssertEqual(decodedUser.name, user.name)
    }

    func testEncryptedMacroBasic() async throws {
        // Test the @Encrypted macro with basic types
        @Encrypted
        struct SecureUser: Codable {
            let id: Int
            let name: String
            let email: String
            let isActive: Bool
        }

        // Create an instance
        let user = SecureUser(
            id: 123,
            name: "John Doe",
            email: "john@example.com",
            isActive: true
        )

        // Create a real keystore and resolver
        let keys = try FFIKeys()
        try keys.mobileInitializeUserRootKey()
        let keystore = FFIKeyStore(keys: keys)

        // Test encryption
        let encrypted = try await user.encryptWithKeystore(keystore, resolver: MockLabelResolver(networkId: nil))
        XCTAssertNotNil(encrypted.encryptedData)
        XCTAssertFalse(encrypted.encryptedData.encryptedData.isEmpty)

        // Test decryption
        let decrypted = try await encrypted.decryptWithKeystore(keystore)
        XCTAssertEqual(decrypted.id, user.id)
        XCTAssertEqual(decrypted.name, user.name)
        XCTAssertEqual(decrypted.email, user.email)
        XCTAssertEqual(decrypted.isActive, user.isActive)
    }

    func testEncryptedMacroWithComplexData() async throws {
        // Test with complex data structures
        @Encrypted
        struct SecureProfile: Codable {
            let id: String
            let name: String
            let metadata: [String: String]
            let tags: [String]
            let settings: UserSettings
        }

        @Plain
        struct UserSettings: Codable {
            let theme: String
            let notifications: Bool
            let language: String
        }

        let profile = SecureProfile(
            id: "user-123",
            name: "Alice Johnson",
            metadata: ["department": "engineering", "role": "developer"],
            tags: ["swift", "ios", "developer"],
            settings: UserSettings(theme: "dark", notifications: true, language: "en")
        )

        let keys = try FFIKeys()
        try keys.mobileInitializeUserRootKey()
        let keystore = FFIKeyStore(keys: keys)
        let resolver = MockLabelResolver(networkId: nil)

        // Test encryption
        let encrypted = try await profile.encryptWithKeystore(keystore, resolver: resolver)
        XCTAssertNotNil(encrypted.encryptedData)

        // Test decryption
        let decrypted = try await encrypted.decryptWithKeystore(keystore)
        XCTAssertEqual(decrypted.id, profile.id)
        XCTAssertEqual(decrypted.name, profile.name)
        XCTAssertEqual(decrypted.metadata, profile.metadata)
        XCTAssertEqual(decrypted.tags, profile.tags)
        XCTAssertEqual(decrypted.settings.theme, profile.settings.theme)
        XCTAssertEqual(decrypted.settings.notifications, profile.settings.notifications)
        XCTAssertEqual(decrypted.settings.language, profile.settings.language)
    }

    func testEncryptedMacroPerformance() async throws {
        // Test performance with larger data
        @Encrypted
        struct SecureData: Codable {
            let id: Int
            let name: String
            let data: [String: String]
            let numbers: [Int]
        }

        // Create larger data structure
        var data: [String: String] = [:]
        var numbers: [Int] = []

        for i in 0 ..< 100 {
            data["key\(i)"] = "value\(i)"
            numbers.append(i)
        }

        let secureData = SecureData(
            id: 1,
            name: "Performance Test",
            data: data,
            numbers: numbers
        )

        let keys = try FFIKeys()
        try keys.mobileInitializeUserRootKey()
        let keystore = FFIKeyStore(keys: keys)
        let resolver = MockLabelResolver(networkId: nil)

        // Test encryption performance
        let encryptionStart = Date()
        let encrypted = try await secureData.encryptWithKeystore(keystore, resolver: resolver)
        let encryptionTime = Date().timeIntervalSince(encryptionStart)

        XCTAssertLessThan(encryptionTime, 1.0, "Encryption should complete within 1 second")

        // Test decryption performance
        let decryptionStart = Date()
        let decrypted = try await encrypted.decryptWithKeystore(keystore)
        let decryptionTime = Date().timeIntervalSince(decryptionStart)

        XCTAssertEqual(decrypted.id, secureData.id)
        XCTAssertEqual(decrypted.name, secureData.name)
        XCTAssertEqual(decrypted.data.count, secureData.data.count)
        XCTAssertEqual(decrypted.numbers.count, secureData.numbers.count)
        XCTAssertLessThan(decryptionTime, 1.0, "Decryption should complete within 1 second")
    }
}

// Real MobileKeyManager is used directly for testing

struct MockLabelResolver: LabelResolver {
    private var networkId: String?

    init(networkId: String? = nil) {
        self.networkId = networkId
    }

    func resolveLabel(_ label: String) -> LabelKeyInfo? {
        // Simple mapping for testing
        let mappings = [
            "secureuser": LabelKeyInfo(profileIds: ["user-profile"], networkId: networkId),
            "secureprofile": LabelKeyInfo(profileIds: ["profile-profile"], networkId: networkId),
            "securedata": LabelKeyInfo(profileIds: ["data-profile"], networkId: networkId),
        ]
        if let hit = mappings[label.lowercased()] { return hit }
        // Default: provide a network-only mapping so envelope has a decryptable network wrap
        if let networkId { return LabelKeyInfo(profileIds: [], networkId: networkId) }
        return nil
    }
}

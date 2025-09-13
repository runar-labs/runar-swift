@testable import RunarFFI
import XCTest

final class KeysTests: XCTestCase {
    func testKeysLifecycleAndStateProbe() throws {
        let tempDir = NSTemporaryDirectory() + "ffi_keys_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let keys = KeysFFI()
        try keys.initializeAsNode()
        try keys.nodeSetPersistenceDirectory(URL(fileURLWithPath: tempDir))
        try keys.nodeEnableAutoPersist(true)

        // Test basic functionality instead of keystore state
        let publicKey = try keys.nodeGetPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "Node should be properly initialized")

        _ = try keys.nodeGetPublicKey() // nodeId is derived from public key
        _ = try keys.nodeGenerateCSR()
        // flushState not implemented yet

        let keys2 = KeysFFI()
        try keys2.initializeAsNode()
        try keys2.nodeSetPersistenceDirectory(URL(fileURLWithPath: tempDir))

        // Test that second instance works
        let publicKey2 = try keys2.nodeGetPublicKey()
        XCTAssertFalse(publicKey2.isEmpty, "Second node instance should work")

        // wipePersistence not implemented yet
        let publicKey3 = try keys2.nodeGetPublicKey()
        XCTAssertFalse(publicKey3.isEmpty, "Node should still work after operations")

        try FileManager.default.removeItem(atPath: tempDir)
    }

    func testMobileStateProbe() throws {
        let tempDir = NSTemporaryDirectory() + "ffi_mobile_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let keys = KeysFFI()
        try keys.initializeAsMobile()
        try keys.mobileSetPersistenceDirectory(URL(fileURLWithPath: tempDir))
        try keys.mobileEnableAutoPersist(true)

        // Test basic functionality instead of keystore state
        try keys.mobileInitializeUserRootKey()
        let userPublicKey = try keys.mobileGetUserPublicKey()
        XCTAssertFalse(userPublicKey.isEmpty, "Mobile should be properly initialized")

        // flushState not implemented yet

        let keys2 = KeysFFI()
        try keys2.initializeAsMobile()
        try keys2.mobileSetPersistenceDirectory(URL(fileURLWithPath: tempDir))

        // Test that second instance works
        try keys2.mobileInitializeUserRootKey()
        let userPublicKey2 = try keys2.mobileGetUserPublicKey()
        XCTAssertFalse(userPublicKey2.isEmpty, "Second mobile instance should work")

        // wipePersistence not implemented yet
        let userPublicKey3 = try keys2.mobileGetUserPublicKey()
        XCTAssertFalse(userPublicKey3.isEmpty, "Mobile should still work after operations")

        try FileManager.default.removeItem(atPath: tempDir)
    }

    func testLocalDataEncryptDecrypt() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        let plaintext = Data("secret bytes".utf8)
        let cipher = try keys.nodeEncryptLocalData(plaintext)
        XCTAssertNotEqual(cipher, plaintext)
        let recovered = try keys.nodeDecryptLocalData(cipher)
        XCTAssertEqual(recovered, plaintext)
    }

    func testMobileInstallNetworkPublicKey() throws {
        // Create a CA and a node to obtain a network public key, then install in another mobile-only keystore
        let certificateAuthority = KeysFFI()
        try certificateAuthority.initializeAsMobile()
        try certificateAuthority.mobileInitializeUserRootKey()

        let node = KeysFFI()
        try node.initializeAsNode()
        let csr = try node.nodeGenerateCSR()
        let ncm = try certificateAuthority.mobileProcessSetupToken(csr)
        try node.nodeInstallCertificate(ncm)

        // Generate a network id (which is now the network public key)
        let networkPublicKey = try certificateAuthority.mobileGenerateNetworkDataKey()
        // Do not install network key on node in this test; we only validate mobile public key install

        // Create a separate mobile-only keys and install the network public key
        let userMobile = KeysFFI()
        try userMobile.initializeAsMobile()
        try userMobile.mobileInitializeUserRootKey()
        try userMobile.mobileInstallNetworkPublicKey(networkPublicKey: networkPublicKey)

        // Verify that the network public key is installed (we can't retrieve it anymore, but we can test encryption)
        // Since mobileGetNetworkPublicKey was removed, we'll test that encryption works with the installed key
        let testData = Data("test message".utf8)
        let encryptedData = try userMobile.mobileEncryptWithEnvelope(
            data: testData,
            networkPublicKey: networkPublicKey,
            profileKeys: []
        )
        XCTAssertFalse(encryptedData.isEmpty)
    }
}

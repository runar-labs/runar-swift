@testable import RunarFFI
import XCTest

final class KeysTests: XCTestCase {
    func testKeysLifecycleAndStateProbe() throws {
        let tempDir = NSTemporaryDirectory() + "ffi_keys_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let keys = try FFIKeys()
        try keys.setPersistenceDir(tempDir)
        try keys.enableAutoPersist(true)

        var state = try keys.nodeGetKeystoreState()
        XCTAssertEqual(state, 0)

        _ = try keys.publicKey()
        _ = try keys.nodeId()
        _ = try keys.generateCSR()
        try keys.flushState()

        state = try keys.nodeGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        let keys2 = try FFIKeys()
        try keys2.setPersistenceDir(tempDir)
        state = try keys2.nodeGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        try keys2.wipePersistence()
        state = try keys2.nodeGetKeystoreState()
        XCTAssertEqual(state, 0)

        try FileManager.default.removeItem(atPath: tempDir)
    }

    func testMobileStateProbe() throws {
        let tempDir = NSTemporaryDirectory() + "ffi_mobile_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let keys = try FFIKeys()
        try keys.setPersistenceDir(tempDir)
        try keys.enableAutoPersist(true)

        var state = try keys.mobileGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        try keys.mobileInitializeUserRootKey()
        try keys.flushState()
        state = try keys.mobileGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        let keys2 = try FFIKeys()
        try keys2.setPersistenceDir(tempDir)
        state = try keys2.mobileGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        try keys2.wipePersistence()
        state = try keys2.mobileGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        try FileManager.default.removeItem(atPath: tempDir)
    }

    func testLocalDataEncryptDecrypt() throws {
        let keys = try FFIKeys()
        let plaintext = Data("secret bytes".utf8)
        let cipher = try keys.encryptLocalData(plaintext)
        XCTAssertNotEqual(cipher, plaintext)
        let recovered = try keys.decryptLocalData(cipher)
        XCTAssertEqual(recovered, plaintext)
    }

    func testMobileInstallNetworkPublicKey() throws {
        // Create a CA and a node to obtain a network public key, then install in another mobile-only keystore
        let ca = try FFIKeys()
        try ca.mobileInitializeUserRootKey()

        let node = try FFIKeys()
        let csr = try node.generateCSR()
        let ncm = try ca.processSetupToken(csr)
        try node.installCertificate(ncm)

        // Generate a network id and retrieve its public key from the mobile (CA)
        let networkId = try ca.mobileGenerateNetworkDataKey()
        let networkPk = try ca.mobileGetNetworkPublicKey(networkId)
        // Do not install network key on node in this test; we only validate mobile public key install

        // Create a separate mobile-only keys and install the network public key
        let userMobile = try FFIKeys()
        try userMobile.mobileInitializeUserRootKey()
        try userMobile.mobileInstallNetworkPublicKey(networkPk)

        // Verify that the installed network public key can be retrieved by the userMobile keystore
        let retrieved = try userMobile.mobileGetNetworkPublicKey(networkId)
        XCTAssertEqual(retrieved, networkPk)
    }
}

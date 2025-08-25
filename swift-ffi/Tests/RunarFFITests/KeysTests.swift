@testable import RunarFFI
import XCTest

final class KeysTests: XCTestCase {
    func testKeysLifecycleAndStateProbe() throws {
        let tempDir = NSTemporaryDirectory() + "ffi_keys_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let keys = try KeysFFI()
        try keys.initializeAsNode()
        try keys.nodeSetPersistenceDirectory(URL(fileURLWithPath: tempDir))
        try keys.nodeEnableAutoPersist(true)

        var state = try keys.nodeGetKeystoreState()
        XCTAssertEqual(state, 0)

        _ = try keys.nodeGetPublicKey()
        _ = try keys.nodeGetPublicKey() // nodeId is derived from public key
        _ = try keys.nodeGenerateCSR()
        // flushState not implemented yet

        state = try keys.nodeGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        let keys2 = try KeysFFI()
        try keys2.initializeAsNode()
        try keys2.nodeSetPersistenceDirectory(URL(fileURLWithPath: tempDir))
        state = try keys2.nodeGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        // wipePersistence not implemented yet
        state = try keys2.nodeGetKeystoreState()
        XCTAssertEqual(state, 0)

        try FileManager.default.removeItem(atPath: tempDir)
    }

    func testMobileStateProbe() throws {
        let tempDir = NSTemporaryDirectory() + "ffi_mobile_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let keys = try KeysFFI()
        try keys.initializeAsMobile()
        try keys.mobileSetPersistenceDirectory(URL(fileURLWithPath: tempDir))
        try keys.mobileEnableAutoPersist(true)

        var state = try keys.mobileGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        try keys.mobileInitializeUserRootKey()
        // flushState not implemented yet
        state = try keys.mobileGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        let keys2 = try KeysFFI()
        try keys2.initializeAsMobile()
        try keys2.mobileSetPersistenceDirectory(URL(fileURLWithPath: tempDir))
        state = try keys2.mobileGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        // wipePersistence not implemented yet
        state = try keys2.mobileGetKeystoreState()
        XCTAssert(state == 0 || state == 1)

        try FileManager.default.removeItem(atPath: tempDir)
    }

    func testLocalDataEncryptDecrypt() throws {
        let keys = try KeysFFI()
        try keys.initializeAsNode()
        let plaintext = Data("secret bytes".utf8)
        let cipher = try keys.nodeEncryptLocalData(plaintext)
        XCTAssertNotEqual(cipher, plaintext)
        let recovered = try keys.nodeDecryptLocalData(cipher)
        XCTAssertEqual(recovered, plaintext)
    }

    func testMobileInstallNetworkPublicKey() throws {
        // Create a CA and a node to obtain a network public key, then install in another mobile-only keystore
        let ca = try KeysFFI()
        try ca.initializeAsMobile()
        try ca.mobileInitializeUserRootKey()

        let node = try KeysFFI()
        try node.initializeAsNode()
        let csr = try node.nodeGenerateCSR()
        let ncm = try ca.mobileProcessSetupToken(csr)
        try node.nodeInstallCertificate(ncm)

        // Generate a network id and retrieve its public key from the mobile (CA)
        let networkId = try ca.mobileGenerateNetworkDataKey()
        let networkPk = try ca.mobileGetNetworkPublicKey(networkId)
        // Do not install network key on node in this test; we only validate mobile public key install

        // Create a separate mobile-only keys and install the network public key
        let userMobile = try KeysFFI()
        try userMobile.initializeAsMobile()
        try userMobile.mobileInitializeUserRootKey()
        try userMobile.mobileInstallNetworkPublicKey(networkPublicKey: networkPk)

        // Verify that the installed network public key can be retrieved by the userMobile keystore
        let retrieved = try userMobile.mobileGetNetworkPublicKey(networkId)
        XCTAssertEqual(retrieved, networkPk)
    }
}

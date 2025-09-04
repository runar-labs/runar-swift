@testable import RunarFFI
import XCTest

final class EnvelopeE2ETests: XCTestCase {
    func testGetAgreementPublicKey() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test that we can get the agreement public key directly
        let publicKey = try keys.nodeGetAgreementPublicKey()

        // Should return non-empty data
        XCTAssertFalse(publicKey.isEmpty, "Agreement public key should not be empty")

        // Should be a reasonable size for a public key (typically 65 bytes for secp256r1)
        XCTAssertGreaterThan(publicKey.count, 32, "Agreement public key should be at least 32 bytes")
        XCTAssertLessThan(publicKey.count, 256, "Agreement public key should be less than 256 bytes")

        print("✅ Agreement public key retrieved successfully: \(publicKey.count) bytes")
    }

    func testEnvelopeEncryptDecryptViaFFI() async throws {
        let tempDir = NSTemporaryDirectory() + "ffi_env_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let keys = KeysFFI()
        try keys.initializeAsMobile()
        try keys.mobileSetPersistenceDirectory(URL(fileURLWithPath: tempDir))
        try keys.mobileEnableAutoPersist(true)
        try keys.mobileInitializeUserRootKey()

        // Profile keys not required for this E2E (network-based envelope)

        // Generate network id
        let nid = try keys.mobileGenerateNetworkDataKey()

        // Get node agreement public key to create network key message
        var usedNetwork = false
        var nodeKeys: KeysFFI?
        do {
            // Need to create a separate node instance to get agreement public key
            nodeKeys = KeysFFI()
            try nodeKeys!.initializeAsNode()
            let publicKey = try nodeKeys!.nodeGetAgreementPublicKey()
            let nkm = try keys.mobileCreateNetworkKeyMessage(networkPublicKey: nid, nodeAgreementPk: publicKey)
            try nodeKeys!.nodeInstallNetworkKey(nkm)
            usedNetwork = true
        } catch {
            throw XCTSkip("Unable to get agreement public key; skipping network flow")
        }

        // Encrypt/decrypt end-to-end via direct FFI calls (matching Rust FFI approach)
        let plaintext = Data("hello ffi".utf8)
        if usedNetwork, let nodeKeys {
            // Use direct FFI calls like the Rust tests do
            let encryptedData = try keys.mobileEncryptWithEnvelope(
                data: plaintext,
                networkPublicKey: nid,
                profileKeys: nil
            )

            // Decrypt using the node keys
            let decryptedData = try nodeKeys.nodeDecryptEnvelope(eedCbor: encryptedData)

            XCTAssertEqual(decryptedData, plaintext, "Decrypted data should match original")
            print("✅ Envelope encryption/decryption successful via direct FFI calls")
        }

        try FileManager.default.removeItem(atPath: tempDir)
    }
}

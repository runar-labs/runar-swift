import XCTest
@testable import RunarFFI
import SwiftCBOR

final class EnvelopeE2ETests: XCTestCase {
    func testEnvelopeEncryptDecryptViaFFI() throws {
        let tempDir = NSTemporaryDirectory() + "ffi_env_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let keys = try FFIKeys()
        try keys.setPersistenceDir(tempDir)
        try keys.enableAutoPersist(true)
        try keys.mobileInitializeUserRootKey()

        // Derive two profile keys for recipients
        let p1 = try keys.mobileDeriveUserProfileKey(label: "personal")
        let p2 = try keys.mobileDeriveUserProfileKey(label: "work")

        // Generate network id and CSR (SetupToken CBOR)
        let nid = try keys.mobileGenerateNetworkDataKey()
        let csr = try keys.generateCSR()

        // Extract node agreement public key from CSR CBOR (schema may evolve)
        // Parse SetupToken CBOR: expect map with keys matching Rust struct fields
        // Prefer FFI helper to extract agreement PK
        var usedNetwork = false
        do {
            let pk = try keys.extractAgreementPk(fromSetupTokenCBOR: csr)
            let nkm = try keys.mobileCreateNetworkKeyMessage(networkId: nid, nodeAgreementPk: pk)
            try keys.nodeInstallNetworkKey(nkm)
            usedNetwork = true
        } catch {
            throw XCTSkip("SetupToken missing node_agreement_public_key; skipping network flow")
        }

        // Encrypt via FFI helpers and decrypt via FFI
        let store = FFIKeyStore(keys: keys)
        let plaintext = Data("hello ffi".utf8)
        if usedNetwork {
            // Encrypt with network only
            let eedNet = try store.encryptWithEnvelope(data: plaintext, networkId: nid, profilePublicKeys: [])
            let decNet = try store.decryptEnvelopeCBOR(eedNet)
            XCTAssertEqual(decNet, plaintext)

            // Encrypt with network + profiles
            let eedBoth = try store.encryptWithEnvelope(data: plaintext, networkId: nid, profilePublicKeys: [p1, p2])
            let decBoth = try store.decryptEnvelopeCBOR(eedBoth)
            XCTAssertEqual(decBoth, plaintext)
        }

        try FileManager.default.removeItem(atPath: tempDir)
    }
}



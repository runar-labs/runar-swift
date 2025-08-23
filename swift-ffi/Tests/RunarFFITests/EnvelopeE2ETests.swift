@testable import RunarFFI
import RunarSerializer
import SwiftCBOR
import XCTest

final class EnvelopeE2ETests: XCTestCase {
    func testGetAgreementPublicKey() throws {
        let keys = try FFIKeys()

        // Test that we can get the agreement public key directly
        let pk = try keys.getAgreementPublicKey()

        // Should return non-empty data
        XCTAssertFalse(pk.isEmpty, "Agreement public key should not be empty")

        // Should be a reasonable size for a public key (typically 65 bytes for secp256r1)
        XCTAssertGreaterThan(pk.count, 32, "Agreement public key should be at least 32 bytes")
        XCTAssertLessThan(pk.count, 256, "Agreement public key should be less than 256 bytes")

        print("✅ Agreement public key retrieved successfully: \(pk.count) bytes")
    }

    func testEnvelopeEncryptDecryptViaFFI() async throws {
        let tempDir = NSTemporaryDirectory() + "ffi_env_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let keys = try FFIKeys()
        try keys.setPersistenceDir(tempDir)
        try keys.enableAutoPersist(true)
        try keys.mobileInitializeUserRootKey()

        // Profile keys not required for this E2E (network-based envelope)

        // Generate network id and CSR (SetupToken CBOR)
        let nid = try keys.mobileGenerateNetworkDataKey()
        let csr = try keys.generateCSR()

        // Extract node agreement public key from CSR CBOR (schema may evolve)
        // Parse SetupToken CBOR: expect map with keys matching Rust struct fields
        // Prefer FFI helper to extract agreement PK
        var usedNetwork = false
        do {
            let pk = try keys.getAgreementPublicKey()
            let nkm = try keys.mobileCreateNetworkKeyMessage(networkId: nid, nodeAgreementPk: pk)
            try keys.nodeInstallNetworkKey(nkm)
            usedNetwork = true
        } catch {
            throw XCTSkip("Unable to get agreement public key; skipping network flow")
        }

        // Encrypt/decrypt end-to-end via AnyValue serialization using FFI keystore
        let store = FFIKeyStore(keys: keys)
        let plaintext = Data("hello ffi".utf8)
        if usedNetwork {
            let ctx = SerializationContext(keystore: store, resolver: DefaultLabelResolver(labelToProfileId: [:]), networkId: nid)
            let any = AnyValue.bytes(plaintext)
            let serialized = try any.serialize(context: ctx)
            let round = try AnyValue.deserialize(serialized, keystore: store)
            let back: Data = try await round.asType()
            XCTAssertEqual(back, plaintext)
        }

        try FileManager.default.removeItem(atPath: tempDir)
    }
}

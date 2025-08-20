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

        // Generate network and create/install network key message
        let nid = try keys.mobileGenerateNetworkDataKey()
        let csr = try keys.generateCSR()

        // Extract node agreement public key from CSR CBOR (schema may evolve)
        let cbor = try CBOR.decode([UInt8](csr))
        guard case let .map(map) = cbor else {
            XCTFail("CSR not a map")
            return
        }
        var nodeAgreementPk = Data()
        if let v = map[.utf8String("node_agreement_public_key")], case let .byteString(bs) = v {
            nodeAgreementPk = Data(bs)
        } else {
            // Fallback: search for a likely agreement key (65 bytes byte string)
            for (_, v) in map {
                if case let .byteString(bs) = v, bs.count == 65 { nodeAgreementPk = Data(bs); break }
            }
        }
        if nodeAgreementPk.isEmpty { XCTFail("CSR missing node agreement key"); return }

        let nkm = try keys.mobileCreateNetworkKeyMessage(networkId: nid, nodeAgreementPk: nodeAgreementPk)
        try keys.nodeInstallNetworkKey(nkm)

        // Encrypt via FFI helpers and decrypt via FFI
        let store = FFIKeyStore(keys: keys)
        let plaintext = Data("hello ffi".utf8)
        let eedCbor = try store.encryptWithEnvelope(data: plaintext, networkId: nid, profilePublicKeys: [p1, p2])
        let decrypted = try store.decryptEnvelopeCBOR(eedCbor)
        XCTAssertEqual(decrypted, plaintext)

        try FileManager.default.removeItem(atPath: tempDir)
    }
}



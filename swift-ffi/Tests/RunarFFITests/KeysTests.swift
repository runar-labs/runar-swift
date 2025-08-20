import XCTest
@testable import RunarFFI
import SwiftCBOR

// Assume import SwiftCBOR at top

final class KeysTests: XCTestCase {
	func testKeysLifecycleAndStateProbe() throws {
		// Use a temporary directory for persistence
		let tempDir = NSTemporaryDirectory() + "ffi_keys_test_\(UUID().uuidString)"
		try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

		let keys = try FFIKeys()
		try keys.setPersistenceDir(tempDir)
		try keys.enableAutoPersist(true)
		let label = "test_node_persistent"
		try keys.registerAppleDeviceKeystore(label: label)

		// Initially, state should be 0 (empty)
		var state = try keys.nodeGetKeystoreState()
		XCTAssertEqual(state, 0)

		// Perform an action that initializes state (e.g., generate CSR, which may trigger internal state creation)
		try keys.mobileInitializeUserRootKey()

		// Generate network data key
		let nid = try keys.mobileGenerateNetworkDataKey()

		let csrCbor = try keys.generateCSR()

		// Parse CSR to get node_agreement_public_key (example using SwiftCBOR)
		if let cbor = try? CBOR.decode(csrCbor),
		   case let .map(dict) = cbor,
		   case let .byteString(pkBytes) = dict[.utf8String("node_agreement_public_key")] {
			let pk = Data(pkBytes)
		} else {
			XCTFail("Failed to parse CSR CBOR")
			return
		}

		let nkm = try keys.mobileCreateNetworkKeyMessage(networkId: nid, nodeAgreementPk: pk)
		try keys.nodeInstallNetworkKey(nkm)

		let nodeId1 = try keys.nodeId()
		XCTAssertFalse(nodeId1.isEmpty)

		let pk = try keys.publicKey()
		XCTAssertFalse(pk.isEmpty)

		// Then proceed with nodeId, pk, csr (if not already called)

		// Flush to persist
		try keys.flushState()

		// Now state should be 1 (initialized)
		state = try keys.nodeGetKeystoreState()
		XCTAssertEqual(state, 1)

		// Create a new keys instance, set same dir, and probe
		let keys2 = try FFIKeys()
		try keys2.setPersistenceDir(tempDir)
		try keys2.registerAppleDeviceKeystore(label: label)
		state = try keys2.nodeGetKeystoreState()
		XCTAssertEqual(state, 1)  // Loads and decrypts existing state

		let nodeId2 = try keys2.nodeId()
		XCTAssertEqual(nodeId1, nodeId2)

		// Clean up: wipe persistence
		try keys2.wipePersistence()
		state = try keys2.nodeGetKeystoreState()
		XCTAssertEqual(state, 0)

		try FileManager.default.removeItem(atPath: tempDir)
	}

	func testMobileStateProbe() throws {
		// Similar to above, use temp dir
		let tempDir = NSTemporaryDirectory() + "ffi_mobile_test_\(UUID().uuidString)"
		try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

		let keys = try FFIKeys()
		try keys.setPersistenceDir(tempDir)
		try keys.enableAutoPersist(true)
		let mobileLabel = "test_mobile_persistent"
		try keys.registerAppleDeviceKeystore(label: mobileLabel)

		// Probe mobile state
		var state = try keys.mobileGetKeystoreState()
		XCTAssertEqual(state, 0)

		// Initialize something mobile-specific (e.g., initialize user root)
		// Assuming rn_keys_mobile_initialize_user_root_key initializes state
		try keys.mobileInitializeUserRootKey()

		try keys.flushState()
		state = try keys.mobileGetKeystoreState()
		XCTAssertEqual(state, 1)

		// New instance loads it
		let keys2 = try FFIKeys()
		try keys2.setPersistenceDir(tempDir)
		try keys2.registerAppleDeviceKeystore(label: mobileLabel)
		state = try keys2.mobileGetKeystoreState()
		XCTAssertEqual(state, 1)

		try keys2.wipePersistence()
		state = try keys2.mobileGetKeystoreState()
		XCTAssertEqual(state, 0)

		try FileManager.default.removeItem(atPath: tempDir)
	}
}



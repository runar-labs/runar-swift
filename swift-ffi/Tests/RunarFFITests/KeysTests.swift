import XCTest
@testable import RunarFFI

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
}



import XCTest
@testable import RunarFFI

final class KeysTests: XCTestCase {
	func testKeysLifecycleAndStateRoundTrip() throws {
		let keys = try FFIKeys()
		let nodeId1 = try keys.nodeId()
		XCTAssertFalse(nodeId1.isEmpty)

		let pk = try keys.publicKey()
		XCTAssertFalse(pk.isEmpty)

		let csr = try keys.generateCSR()
		XCTAssertFalse(csr.isEmpty)

		let exported = try keys.exportState()
		XCTAssertFalse(exported.isEmpty)

		let keys2 = try FFIKeys()
		try keys2.importState(exported)
		let nodeId2 = try keys2.nodeId()
		XCTAssertEqual(nodeId1, nodeId2)
	}

	func testMobileStateRoundTrip() throws {
		let keys = try FFIKeys()
		let mobileState = try keys.mobileExportState()
		XCTAssertFalse(mobileState.isEmpty)
		let keys2 = try FFIKeys()
		try keys2.mobileImportState(mobileState)
		XCTAssertEqual(try keys.nodeId(), try keys2.nodeId())
	}
}



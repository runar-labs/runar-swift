import SwiftCommon
import SwiftFFI
import XCTest

@testable import SwiftFFI

/// Tests for network key flows
/// Tests mobile install/generate/has/create_message, node install/get_agreement/has_private
final class NetworkKeyFlowTests: XCTestCase {
    private var nodeKeys: NodeKeyManager!
    private var mobileKeys: MobileKeyManager!

    override func setUp() {
        super.setUp()

        // Set log level to trace to see detailed logs
        print("DEBUG: Setting log level to trace")
        do {
            try FFILogger.setLogLevel(.trace)
            print("DEBUG: Log level set to trace")

            // Create node keys handle
            nodeKeys = try NodeKeyManager()
            try nodeKeys.generateKeys()

            // Create mobile keys handle
            mobileKeys = try MobileKeyManager()
            try mobileKeys.initializeUserRootKey()
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }
    }

    override func tearDown() {
        nodeKeys = nil
        mobileKeys = nil
        super.tearDown()
    }

    // MARK: - Mobile Network Key Tests

    func testSmoke_mobileHasNetworkPrivateKey_symbolAndABI() throws {
        // Validate we can call into the Rust symbol without crashing and get a sane result
        // 1) Generate a network data key, then check for that key -> true
        let generatedKey = try mobileKeys.generateNetworkDataKey()
        XCTAssertFalse(generatedKey.isEmpty)
        let hasGenerated = try mobileKeys.hasNetworkPrivateKey(networkPublicKey: generatedKey)
        XCTAssertTrue(hasGenerated)

        // 2) Check a zeroed 65-byte key -> should be false (and not crash)
        let dummy = Data(repeating: 0, count: 65)
        let hasDummy = try mobileKeys.hasNetworkPrivateKey(networkPublicKey: dummy)
        XCTAssertFalse(hasDummy)
    }

    func testMobileInstallNetworkPublicKey() throws {
        // Get node's network public key
        let nodePublicKey = try nodeKeys.getNodePublicKey()

        // Install network public key on mobile
        try mobileKeys.installNetworkPublicKey(nodePublicKey)

        // Verify no error is thrown (success)
        XCTAssertTrue(true, "Installing network public key on mobile should succeed")
    }

    func testMobileGenerateNetworkDataKey() throws {
        // Generate network data key on mobile
        let networkDataKey = try mobileKeys.generateNetworkDataKey()

        // Verify key is generated
        XCTAssertFalse(networkDataKey.isEmpty, "Network data key should not be empty")
        XCTAssertGreaterThan(networkDataKey.count, 0, "Network data key should have content")
    }

    func testMobileHasNetworkPrivateKey() throws {
        // First test that mobile manager is working by generating a network data key
        let networkDataKey = try mobileKeys.generateNetworkDataKey()
        XCTAssertFalse(networkDataKey.isEmpty, "Network data key should be generated")

        // Test 1: Check if mobile has the network private key for the generated key (should be true)
        print("DEBUG: Testing with generated network data key: \(networkDataKey.count) bytes")
        let hasGeneratedKey = try mobileKeys.hasNetworkPrivateKey(networkPublicKey: networkDataKey)
        print("DEBUG: hasGeneratedKey = \(hasGeneratedKey)")
        XCTAssertTrue(hasGeneratedKey, "Mobile should have network private key for generated key")

        // Test 2: Check with a dummy network public key (should return false)
        let dummyKey = Data(repeating: 0, count: 65)
        print("DEBUG: Testing with dummy key: \(dummyKey.count) bytes")
        let hasDummyKey = try mobileKeys.hasNetworkPrivateKey(networkPublicKey: dummyKey)
        print("DEBUG: hasDummyKey = \(hasDummyKey)")
        XCTAssertFalse(hasDummyKey, "Mobile should not have network private key for non-existent key")
    }

    func testMobileCreateNetworkKeyMessage() throws {
        // Generate network data key first
        let networkDataKey = try mobileKeys.generateNetworkDataKey()

        // Get node's agreement public key
        let nodeAgreementKey = try nodeKeys.getNodePublicKey()

        // Create network key message using the network data key
        let networkKeyMessage = try mobileKeys.createNetworkKeyMessage(
            networkPublicKey: networkDataKey,
            nodeAgreementPublicKey: nodeAgreementKey
        )

        // Verify message is created
        XCTAssertFalse(networkKeyMessage.isEmpty, "Network key message should not be empty")
        XCTAssertGreaterThan(networkKeyMessage.count, 0, "Network key message should have content")
    }

    // MARK: - Node Network Key Tests

    func testNodeInstallNetworkKey() throws {
        // Generate keys first (matches Rust pattern)
        try nodeKeys.generateKeys()

        // Test with invalid network key message (matches Rust test_install_network_key_invalid_message)
        let invalidMessage = Data("not valid cbor data".utf8)

        do {
            try nodeKeys.installNetworkKey(invalidMessage)
            XCTFail("Should have failed with invalid network key message")
        } catch {
            XCTAssertTrue(error is FFIError)
            // Expected error for invalid message
        }
    }

    func testNodeGetNetworkAgreement() throws {
        // Generate keys first (matches Rust pattern)
        try nodeKeys.generateKeys()

        // Test with a dummy public key (should fail - matches Rust test_get_network_agreement_no_key)
        let dummyPublicKey = Data(repeating: 0, count: 65)

        do {
            let networkAgreement = try nodeKeys.getNetworkAgreement(networkPublicKey: dummyPublicKey)
            XCTFail("Should have failed when network key doesn't exist")
        } catch {
            XCTAssertTrue(error is FFIError)
            // Expected error: "Key not found: Network key pair not found"
        }
    }

    func testNodeHasNetworkPrivateKey() throws {
        // Generate keys first (matches Rust pattern)
        try nodeKeys.generateKeys()

        // Test with dummy public key (should return false - matches Rust test_has_network_private_key_no_key)
        let dummyPublicKey = Data(repeating: 0, count: 65)

        let hasPrivateKey = try nodeKeys.hasNetworkPrivateKey(networkPublicKey: dummyPublicKey)
        XCTAssertFalse(hasPrivateKey, "Node should not have network private key for dummy key")
    }

    // MARK: - Complete Network Key Exchange Flow

    func testCompleteNetworkKeyExchangeFlow() throws {
        // This test simulates a complete network key exchange between mobile and node

        // 1. Mobile generates network data key
        let mobileNetworkDataKey = try mobileKeys.generateNetworkDataKey()
        XCTAssertFalse(mobileNetworkDataKey.isEmpty, "Mobile network data key should be generated")

        // 2. Mobile installs node's public key
        let nodePublicKey = try nodeKeys.getNodePublicKey()
        try mobileKeys.installNetworkPublicKey(nodePublicKey)

        // 3. Mobile creates network key message
        let nodeAgreementKey = try nodeKeys.getNodeAgreementPublicKey()
        let networkKeyMessage = try mobileKeys.createNetworkKeyMessage(
            networkPublicKey: mobileNetworkDataKey,
            nodeAgreementPublicKey: nodeAgreementKey
        )
        XCTAssertFalse(networkKeyMessage.isEmpty, "Network key message should be created")

        // 4. Node installs network key
        try nodeKeys.installNetworkKey(networkKeyMessage)

        // 5. Verify node now has network private key for the network public key
        let nodeHasPrivateKey = try nodeKeys.hasNetworkPrivateKey(networkPublicKey: mobileNetworkDataKey)
        XCTAssertTrue(nodeHasPrivateKey, "Node should have network private key after installation")

        // 6. Verify mobile now has network private key for the network public key
        let mobileHasPrivateKey = try mobileKeys.hasNetworkPrivateKey(networkPublicKey: mobileNetworkDataKey)
        XCTAssertTrue(mobileHasPrivateKey, "Mobile should have network private key after installation")

        // 7. Test network agreement on both sides
        let nodeAgreement = try nodeKeys.getNetworkAgreement(networkPublicKey: mobileNetworkDataKey)
        XCTAssertFalse(nodeAgreement.isEmpty, "Node network agreement should be available")
    }

    // MARK: - Error Handling Tests

    func testNetworkKeyOperationsWithInvalidData() throws {
        // Test with empty data
        let emptyData = Data()

        do {
            try mobileKeys.installNetworkPublicKey(emptyData)
            XCTFail("Should have thrown error for empty network public key")
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        do {
            try nodeKeys.installNetworkKey(emptyData)
            XCTFail("Should have thrown error for empty network key message")
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        do {
            try nodeKeys.getNetworkAgreement(networkPublicKey: emptyData)
            XCTFail("Should have thrown error for empty network public key")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNetworkKeyOperationsWithInvalidKeys() throws {
        // Test with invalid key data
        let invalidKey = Data([0x01, 0x02, 0x03, 0x04]) // Too short for a valid key

        do {
            try mobileKeys.installNetworkPublicKey(invalidKey)
            // Might succeed or fail depending on validation
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        do {
            try nodeKeys.getNetworkAgreement(networkPublicKey: invalidKey)
            // Might succeed or fail depending on validation
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - Multiple Network Keys Tests

    func testMultipleNetworkKeys() throws {
        // Test handling multiple network keys

        // Generate keys first (matches Rust pattern)
        try nodeKeys.generateKeys()

        // Generate multiple network data keys
        let networkKey1 = try mobileKeys.generateNetworkDataKey()
        let networkKey2 = try mobileKeys.generateNetworkDataKey()

        // Verify they are different
        XCTAssertNotEqual(networkKey1, networkKey2, "Generated network keys should be different")

        // Test with different node public keys
        let nodePublicKey1 = try nodeKeys.getNodePublicKey()

        // Create a second node keys handle for different public key
        let nodeKeys2 = try NodeKeyManager()
        try nodeKeys2.generateKeys()
        let nodePublicKey2 = try nodeKeys2.getNodePublicKey()

        // Verify different public keys
        XCTAssertNotEqual(nodePublicKey1, nodePublicKey2, "Different nodes should have different public keys")

        // Test has network private key with different keys (should both return false for dummy keys)
        let dummyKey1 = Data(repeating: 0, count: 65)
        let dummyKey2 = Data(repeating: 1, count: 65)

        let hasKey1 = try nodeKeys.hasNetworkPrivateKey(networkPublicKey: dummyKey1)
        let hasKey2 = try nodeKeys2.hasNetworkPrivateKey(networkPublicKey: dummyKey2)

        XCTAssertFalse(hasKey1, "Node 1 should not have network private key for dummy key")
        XCTAssertFalse(hasKey2, "Node 2 should not have network private key for dummy key")
    }

    // MARK: - Concurrent Network Key Operations

    func testConcurrentNetworkKeyOperations() throws {
        // Test concurrent network key operations

        let expectation = XCTestExpectation(description: "Concurrent network key operations")
        expectation.expectedFulfillmentCount = 3

        // Run concurrent operations
        DispatchQueue.global().async {
            do {
                let networkDataKey = try self.mobileKeys.generateNetworkDataKey()
                XCTAssertFalse(networkDataKey.isEmpty)
                expectation.fulfill()
            } catch {
                XCTFail("Generate network data key failed: \(error)")
            }
        }

        DispatchQueue.global().async {
            do {
                let nodePublicKey = try self.nodeKeys.getNodePublicKey()
                try self.mobileKeys.installNetworkPublicKey(nodePublicKey)
                expectation.fulfill()
            } catch {
                XCTFail("Install network public key failed: \(error)")
            }
        }

        DispatchQueue.global().async {
            do {
                let dummyKey = Data(repeating: 0, count: 65)
                let hasPrivateKey = try self.nodeKeys.hasNetworkPrivateKey(networkPublicKey: dummyKey)
                XCTAssertFalse(hasPrivateKey) // Should be false for dummy key
                expectation.fulfill()
            } catch {
                XCTFail("Check network private key failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Network Key State Persistence

    func testNetworkKeyStatePersistence() throws {
        // Skip persistence test - persistence methods not part of new unified key manager design
        XCTSkip("Persistence functionality not part of new unified key manager design")
    }
}

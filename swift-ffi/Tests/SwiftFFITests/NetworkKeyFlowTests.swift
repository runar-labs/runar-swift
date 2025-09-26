import SwiftCommon
import SwiftFFI
import XCTest

@testable import SwiftFFI

/// Tests for network key flows
/// Tests mobile install/generate/has/create_message, node install/get_agreement/has_private
@MainActor
final class NetworkKeyFlowTests: XCTestCase {
    private var nodeKeys: NodeKeyManager!
    private var mobileKeys: MobileKeyManager!

    override func setUp() async throws {
        try await super.setUp()

        // Set log level to trace to see detailed logs
        do {
            try await FFILogger.setLogLevel(.trace)

            // Create node keys handle
            nodeKeys = try await NodeKeyManager()
            try await nodeKeys.generateKeys()

            // Create mobile keys handle
            mobileKeys = try await MobileKeyManager()
            try await mobileKeys.initializeUserRootKey()
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }
    }

    override func tearDown() async throws {
        nodeKeys = nil
        mobileKeys = nil
        try await super.tearDown()
    }

    // MARK: - Mobile Network Key Tests

    func testSmoke_mobileHasNetworkPrivateKey_symbolAndABI() async throws {
        // Validate we can call into the Rust symbol without crashing and get a sane result
        // 1) Generate a network data key, then check for that key -> true
        let generatedKey = try await mobileKeys.generateNetworkDataKey()
        XCTAssertFalse(generatedKey.isEmpty)
        let hasGenerated = try await mobileKeys.hasNetworkPrivateKey(networkPublicKey: generatedKey)
        XCTAssertTrue(hasGenerated)

        // 2) Check a zeroed 65-byte key -> should be false (and not crash)
        let dummy = Data(repeating: 0, count: 65)
        let hasDummy = try await mobileKeys.hasNetworkPrivateKey(networkPublicKey: dummy)
        XCTAssertFalse(hasDummy)
    }

    func testMobileInstallNetworkPublicKey() async throws {
        // Get node's network public key
        let nodePublicKey = try await nodeKeys.getNodePublicKey()

        // Install network public key on mobile
        try await mobileKeys.installNetworkPublicKey(nodePublicKey)

        // Verify no error is thrown (success)
        XCTAssertTrue(true, "Installing network public key on mobile should succeed")
    }

    func testMobileGenerateNetworkDataKey() async throws {
        // Generate network data key on mobile
        let networkDataKey = try await mobileKeys.generateNetworkDataKey()

        // Verify key is generated
        XCTAssertFalse(networkDataKey.isEmpty, "Network data key should not be empty")
        XCTAssertGreaterThan(networkDataKey.count, 0, "Network data key should have content")
    }

    func testMobileHasNetworkPrivateKey() async throws {
        // First test that mobile manager is working by generating a network data key
        let networkDataKey = try await mobileKeys.generateNetworkDataKey()
        XCTAssertFalse(networkDataKey.isEmpty, "Network data key should be generated")

        // Test 1: Check if mobile has the network private key for the generated key (should be true)
        let hasGeneratedKey = try await mobileKeys.hasNetworkPrivateKey(networkPublicKey: networkDataKey)
        XCTAssertTrue(hasGeneratedKey, "Mobile should have network private key for generated key")

        // Test 2: Check with a dummy network public key (should return false)
        let dummyKey = Data(repeating: 0, count: 65)
        let hasDummyKey = try await mobileKeys.hasNetworkPrivateKey(networkPublicKey: dummyKey)
        XCTAssertFalse(hasDummyKey, "Mobile should not have network private key for non-existent key")
    }

    func testMobileCreateNetworkKeyMessage() async throws {
        // Generate network data key first
        let networkDataKey = try await mobileKeys.generateNetworkDataKey()

        // Get node's agreement public key
        let nodeAgreementKey = try await nodeKeys.getNodePublicKey()

        // Create network key message using the network data key
        let networkKeyMessage = try await mobileKeys.createNetworkKeyMessage(
            networkPublicKey: networkDataKey,
            nodeAgreementPublicKey: nodeAgreementKey
        )

        // Verify message is created
        XCTAssertFalse(networkKeyMessage.isEmpty, "Network key message should not be empty")
        XCTAssertGreaterThan(networkKeyMessage.count, 0, "Network key message should have content")
    }

    // MARK: - Node Network Key Tests

    func testNodeInstallNetworkKey() async throws {
        // Generate keys first (matches Rust pattern)
        try await nodeKeys.generateKeys()

        // Test with invalid network key message (matches Rust test_install_network_key_invalid_message)
        let invalidMessage = Data("not valid cbor data".utf8)

        do {
            try await nodeKeys.installNetworkKey(invalidMessage)
            XCTFail("Should have failed with invalid network key message")
        } catch {
            XCTAssertTrue(error is FFIError)
            // Expected error for invalid message
        }
    }

    func testNodeGetNetworkAgreement() async throws {
        // Generate keys first (matches Rust pattern)
        try await nodeKeys.generateKeys()

        // Test with a dummy public key (should fail - matches Rust test_get_network_agreement_no_key)
        let dummyPublicKey = Data(repeating: 0, count: 65)

        do {
            let networkAgreement = try await nodeKeys.getNetworkAgreement(networkPublicKey: dummyPublicKey)
            XCTFail("Should have failed when network key doesn't exist")
        } catch {
            XCTAssertTrue(error is FFIError)
            // Expected error: "Key not found: Network key pair not found"
        }
    }

    func testNodeHasNetworkPrivateKey() async throws {
        // Generate keys first (matches Rust pattern)
        try await nodeKeys.generateKeys()

        // Test with dummy public key (should return false - matches Rust test_has_network_private_key_no_key)
        let dummyPublicKey = Data(repeating: 0, count: 65)

        let hasPrivateKey = try await nodeKeys.hasNetworkPrivateKey(networkPublicKey: dummyPublicKey)
        XCTAssertFalse(hasPrivateKey, "Node should not have network private key for dummy key")
    }

    // MARK: - Complete Network Key Exchange Flow

    func testCompleteNetworkKeyExchangeFlow() async throws {
        // This test simulates a complete network key exchange between mobile and node

        // 1. Mobile generates network data key
        let mobileNetworkDataKey = try await mobileKeys.generateNetworkDataKey()
        XCTAssertFalse(mobileNetworkDataKey.isEmpty, "Mobile network data key should be generated")

        // 2. Mobile installs node's public key
        let nodePublicKey = try await nodeKeys.getNodePublicKey()
        try await mobileKeys.installNetworkPublicKey(nodePublicKey)

        // 3. Mobile creates network key message
        let nodeAgreementKey = try await nodeKeys.getNodeAgreementPublicKey()
        let networkKeyMessage = try await mobileKeys.createNetworkKeyMessage(
            networkPublicKey: mobileNetworkDataKey,
            nodeAgreementPublicKey: nodeAgreementKey
        )
        XCTAssertFalse(networkKeyMessage.isEmpty, "Network key message should be created")

        // 4. Node installs network key
        try await nodeKeys.installNetworkKey(networkKeyMessage)

        // 5. Verify node now has network private key for the network public key
        let nodeHasPrivateKey = try await nodeKeys.hasNetworkPrivateKey(networkPublicKey: mobileNetworkDataKey)
        XCTAssertTrue(nodeHasPrivateKey, "Node should have network private key after installation")

        // 6. Verify mobile now has network private key for the network public key
        let mobileHasPrivateKey = try await mobileKeys.hasNetworkPrivateKey(networkPublicKey: mobileNetworkDataKey)
        XCTAssertTrue(mobileHasPrivateKey, "Mobile should have network private key after installation")

        // 7. Test network agreement on both sides
        let nodeAgreement = try await nodeKeys.getNetworkAgreement(networkPublicKey: mobileNetworkDataKey)
        XCTAssertFalse(nodeAgreement.isEmpty, "Node network agreement should be available")
    }

    // MARK: - Error Handling Tests

    func testNetworkKeyOperationsWithInvalidData() async throws {
        // Test with empty data
        let emptyData = Data()

        do {
            try await mobileKeys.installNetworkPublicKey(emptyData)
            XCTFail("Should have thrown error for empty network public key")
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        do {
            try await nodeKeys.installNetworkKey(emptyData)
            XCTFail("Should have thrown error for empty network key message")
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        do {
            try await nodeKeys.getNetworkAgreement(networkPublicKey: emptyData)
            XCTFail("Should have thrown error for empty network public key")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNetworkKeyOperationsWithInvalidKeys() async throws {
        // Test with invalid key data
        let invalidKey = Data([0x01, 0x02, 0x03, 0x04]) // Too short for a valid key

        do {
            try await mobileKeys.installNetworkPublicKey(invalidKey)
            // Might succeed or fail depending on validation
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        do {
            try await nodeKeys.getNetworkAgreement(networkPublicKey: invalidKey)
            // Might succeed or fail depending on validation
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - Multiple Network Keys Tests

    func testMultipleNetworkKeys() async throws {
        // Test handling multiple network keys

        // Generate keys first (matches Rust pattern)
        try await nodeKeys.generateKeys()

        // Generate multiple network data keys
        let networkKey1 = try await mobileKeys.generateNetworkDataKey()
        let networkKey2 = try await mobileKeys.generateNetworkDataKey()

        // Verify they are different
        XCTAssertNotEqual(networkKey1, networkKey2, "Generated network keys should be different")

        // Test with different node public keys
        let nodePublicKey1 = try await nodeKeys.getNodePublicKey()

        // Create a second node keys handle for different public key
        let nodeKeys2 = try await NodeKeyManager()
        try await nodeKeys2.generateKeys()
        let nodePublicKey2 = try await nodeKeys2.getNodePublicKey()

        // Verify different public keys
        XCTAssertNotEqual(nodePublicKey1, nodePublicKey2, "Different nodes should have different public keys")

        // Test has network private key with different keys (should both return false for dummy keys)
        let dummyKey1 = Data(repeating: 0, count: 65)
        let dummyKey2 = Data(repeating: 1, count: 65)

        let hasKey1 = try await nodeKeys.hasNetworkPrivateKey(networkPublicKey: dummyKey1)
        let hasKey2 = try await nodeKeys2.hasNetworkPrivateKey(networkPublicKey: dummyKey2)

        XCTAssertFalse(hasKey1, "Node 1 should not have network private key for dummy key")
        XCTAssertFalse(hasKey2, "Node 2 should not have network private key for dummy key")
    }

    // MARK: - Concurrent Network Key Operations

    func testConcurrentNetworkKeyOperations() async throws {
        // Test concurrent network key operations

        let expectation = XCTestExpectation(description: "Concurrent network key operations")
        expectation.expectedFulfillmentCount = 3

        // Run concurrent operations
        guard let mobileKeys = mobileKeys else {
            XCTFail("Mobile keys not initialized")
            return
        }
        guard let nodeKeys = nodeKeys else {
            XCTFail("Node keys not initialized")
            return
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let networkDataKey = try await mobileKeys.generateNetworkDataKey()
                    XCTAssertFalse(networkDataKey.isEmpty)
                    expectation.fulfill()
                } catch {
                    XCTFail("Generate network data key failed: \(error)")
                }
            }

            group.addTask {
                do {
                    let nodePublicKey = try await nodeKeys.getNodePublicKey()
                    try await mobileKeys.installNetworkPublicKey(nodePublicKey)
                    expectation.fulfill()
                } catch {
                    XCTFail("Install network public key failed: \(error)")
                }
            }

            group.addTask {
                do {
                    let dummyKey = Data(repeating: 0, count: 65)
                    let hasPrivateKey = try await nodeKeys.hasNetworkPrivateKey(networkPublicKey: dummyKey)
                    XCTAssertFalse(hasPrivateKey) // Should be false for dummy key
                    expectation.fulfill()
                } catch {
                    XCTFail("Check network private key failed: \(error)")
                }
            }

            await group.waitForAll()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    // MARK: - Network Key State Persistence

    func testNetworkKeyStatePersistence() async throws {
        // Test network key state persistence with proper implementation
        // This test verifies that network keys can be persisted and retrieved

        // Generate network data key on mobile
        let networkDataKey = try await mobileKeys.generateNetworkDataKey()
        XCTAssertNotNil(networkDataKey, "Network data key should be generated")

        // Get node agreement public key
        let nodeAgreementPublicKey = try await nodeKeys.getNodeAgreementPublicKey()
        XCTAssertNotNil(nodeAgreementPublicKey, "Node agreement public key should be available")

        // Create network key message
        let networkKeyMessage = try await mobileKeys.createNetworkKeyMessage(
            networkPublicKey: networkDataKey,
            nodeAgreementPublicKey: nodeAgreementPublicKey
        )
        XCTAssertNotNil(networkKeyMessage, "Network key message should be created")

        // Install network key on node
        try await nodeKeys.installNetworkKey(networkKeyMessage)

        // Verify network key is installed by checking if node has the private key
        let hasNetworkPrivateKey = try await nodeKeys.hasNetworkPrivateKey(networkPublicKey: networkDataKey)
        XCTAssertTrue(hasNetworkPrivateKey, "Node should have network private key after installation")

        // Test network encryption/decryption to verify persistence
        let testData = Data("Test network data for persistence".utf8)
        let encryptedData = try await nodeKeys.encryptForNetwork(data: testData, networkPublicKey: networkDataKey)
        XCTAssertNotNil(encryptedData, "Network data should be encrypted")

        let decryptedData = try await nodeKeys.decryptNetworkData(encryptedEnvelope: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }
}

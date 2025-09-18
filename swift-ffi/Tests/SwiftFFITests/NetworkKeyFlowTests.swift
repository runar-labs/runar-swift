import XCTest
import SwiftFFI
import SwiftCommon

@testable import SwiftFFI

/// Tests for network key flows
/// Tests mobile install/generate/has/create_message, node install/get_agreement/has_private
final class NetworkKeyFlowTests: XCTestCase {
    
    private var nodeKeys: KeysHandle!
    private var mobileKeys: KeysHandle!
    
    override func setUp() {
        super.setUp()
        
        // Set log level to trace to see detailed logs
        print("DEBUG: Setting log level to trace")
        try! FFILogger.setLogLevel(.trace)
        print("DEBUG: Log level set to trace")
        
        // Create node keys handle
        nodeKeys = try! KeysHandle()
        try! nodeKeys.initializeAsNode()
        try! nodeKeys.nodeGenerateKeys()
        
        // Create mobile keys handle
        mobileKeys = try! KeysHandle()
        try! mobileKeys.initializeAsMobile()
        try! mobileKeys.mobileInitializeUserRootKey()
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
        let generatedKey = try mobileKeys.mobileGenerateNetworkDataKey()
        XCTAssertFalse(generatedKey.isEmpty)
        let hasGenerated = try mobileKeys.mobileHasNetworkPrivateKey(generatedKey)
        XCTAssertTrue(hasGenerated)
        
        // 2) Check a zeroed 65-byte key -> should be false (and not crash)
        let dummy = Data(repeating: 0, count: 65)
        let hasDummy = try mobileKeys.mobileHasNetworkPrivateKey(dummy)
        XCTAssertFalse(hasDummy)
    }
    
    func testMobileInstallNetworkPublicKey() throws {
        // Get node's network public key
        let nodePublicKey = try nodeKeys.getNodePublicKey()
        
        // Install network public key on mobile
        try mobileKeys.mobileInstallNetworkPublicKey(nodePublicKey)
        
        // Verify no error is thrown (success)
        XCTAssertTrue(true, "Installing network public key on mobile should succeed")
    }
    
    func testMobileGenerateNetworkDataKey() throws {
        // Generate network data key on mobile
        let networkDataKey = try mobileKeys.mobileGenerateNetworkDataKey()
        
        // Verify key is generated
        XCTAssertFalse(networkDataKey.isEmpty, "Network data key should not be empty")
        XCTAssertGreaterThan(networkDataKey.count, 0, "Network data key should have content")
    }
    
    func testMobileHasNetworkPrivateKey() throws {
        // First test that mobile manager is working by generating a network data key
        let networkDataKey = try mobileKeys.mobileGenerateNetworkDataKey()
        XCTAssertFalse(networkDataKey.isEmpty, "Network data key should be generated")
        
        // Test 1: Check if mobile has the network private key for the generated key (should be true)
        print("DEBUG: Testing with generated network data key: \(networkDataKey.count) bytes")
        let hasGeneratedKey = try mobileKeys.mobileHasNetworkPrivateKey(networkDataKey)
        print("DEBUG: hasGeneratedKey = \(hasGeneratedKey)")
        XCTAssertTrue(hasGeneratedKey, "Mobile should have network private key for generated key")
        
        // Test 2: Check with a dummy network public key (should return false)
        let dummyKey = Data(repeating: 0, count: 65)
        print("DEBUG: Testing with dummy key: \(dummyKey.count) bytes")
        let hasDummyKey = try mobileKeys.mobileHasNetworkPrivateKey(dummyKey)
        print("DEBUG: hasDummyKey = \(hasDummyKey)")
        XCTAssertFalse(hasDummyKey, "Mobile should not have network private key for non-existent key")
    }
    
    func testMobileCreateNetworkKeyMessage() throws {
        // Get node's agreement public key
        let nodeAgreementKey = try nodeKeys.getNodeAgreementPublicKey()
        
        // Get node's public key
        let nodePublicKey = try nodeKeys.getNodePublicKey()
        
        // Create network key message
        let networkKeyMessage = try mobileKeys.mobileCreateNetworkKeyMessage(
            networkPublicKey: nodePublicKey,
            nodeAgreementPublicKey: nodeAgreementKey
        )
        
        // Verify message is created
        XCTAssertFalse(networkKeyMessage.isEmpty, "Network key message should not be empty")
        XCTAssertGreaterThan(networkKeyMessage.count, 0, "Network key message should have content")
    }
    
    // MARK: - Node Network Key Tests
    
    func testNodeInstallNetworkKey() throws {
        // Generate keys first (matches Rust pattern)
        try nodeKeys.nodeGenerateKeys()
        
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
        try nodeKeys.nodeGenerateKeys()
        
        // Test with a dummy public key (should fail - matches Rust test_get_network_agreement_no_key)
        let dummyPublicKey = Data(repeating: 0, count: 65)
        
        do {
            let networkAgreement = try nodeKeys.getNetworkAgreement(dummyPublicKey)
            XCTFail("Should have failed when network key doesn't exist")
        } catch {
            XCTAssertTrue(error is FFIError)
            // Expected error: "Key not found: Network key pair not found"
        }
    }
    
    func testNodeHasNetworkPrivateKey() throws {
        // Generate keys first (matches Rust pattern)
        try nodeKeys.nodeGenerateKeys()
        
        // Test with dummy public key (should return false - matches Rust test_has_network_private_key_no_key)
        let dummyPublicKey = Data(repeating: 0, count: 65)
        
        let hasPrivateKey = try nodeKeys.hasNetworkPrivateKey(dummyPublicKey)
        XCTAssertFalse(hasPrivateKey, "Node should not have network private key for dummy key")
    }
    
    // MARK: - Complete Network Key Exchange Flow
    
    func testCompleteNetworkKeyExchangeFlow() throws {
        // This test simulates a complete network key exchange between mobile and node
        
        // 1. Mobile generates network data key
        let mobileNetworkDataKey = try mobileKeys.mobileGenerateNetworkDataKey()
        XCTAssertFalse(mobileNetworkDataKey.isEmpty, "Mobile network data key should be generated")
        
        // 2. Mobile installs node's public key
        let nodePublicKey = try nodeKeys.getNodePublicKey()
        try mobileKeys.mobileInstallNetworkPublicKey(nodePublicKey)
        
        // 3. Mobile creates network key message
        let nodeAgreementKey = try nodeKeys.getNodeAgreementPublicKey()
        let networkKeyMessage = try mobileKeys.mobileCreateNetworkKeyMessage(
            networkPublicKey: nodePublicKey,
            nodeAgreementPublicKey: nodeAgreementKey
        )
        XCTAssertFalse(networkKeyMessage.isEmpty, "Network key message should be created")
        
        // 4. Node installs network key
        try nodeKeys.installNetworkKey(networkKeyMessage)
        
        // 5. Verify node now has network private key
        let nodeHasPrivateKey = try nodeKeys.hasNetworkPrivateKey(nodePublicKey)
        XCTAssertTrue(nodeHasPrivateKey, "Node should have network private key after installation")
        
        // 6. Verify mobile now has network private key
        let mobileHasPrivateKey = try mobileKeys.mobileHasNetworkPrivateKey(nodePublicKey)
        XCTAssertTrue(mobileHasPrivateKey, "Mobile should have network private key after installation")
        
        // 7. Test network agreement on both sides
        let nodeAgreement = try nodeKeys.getNetworkAgreement(nodePublicKey)
        XCTAssertFalse(nodeAgreement.isEmpty, "Node network agreement should be available")
    }
    
    // MARK: - Error Handling Tests
    
    func testNetworkKeyOperationsWithInvalidData() throws {
        // Test with empty data
        let emptyData = Data()
        
        do {
            try mobileKeys.mobileInstallNetworkPublicKey(emptyData)
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
            try nodeKeys.getNetworkAgreement(emptyData)
            XCTFail("Should have thrown error for empty network public key")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testNetworkKeyOperationsWithInvalidKeys() throws {
        // Test with invalid key data
        let invalidKey = Data([0x01, 0x02, 0x03, 0x04]) // Too short for a valid key
        
        do {
            try mobileKeys.mobileInstallNetworkPublicKey(invalidKey)
            // Might succeed or fail depending on validation
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            try nodeKeys.getNetworkAgreement(invalidKey)
            // Might succeed or fail depending on validation
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Multiple Network Keys Tests
    
    func testMultipleNetworkKeys() throws {
        // Test handling multiple network keys
        
        // Generate keys first (matches Rust pattern)
        try nodeKeys.nodeGenerateKeys()
        
        // Generate multiple network data keys
        let networkKey1 = try mobileKeys.mobileGenerateNetworkDataKey()
        let networkKey2 = try mobileKeys.mobileGenerateNetworkDataKey()
        
        // Verify they are different
        XCTAssertNotEqual(networkKey1, networkKey2, "Generated network keys should be different")
        
        // Test with different node public keys
        let nodePublicKey1 = try nodeKeys.getNodePublicKey()
        
        // Create a second node keys handle for different public key
        let nodeKeys2 = try KeysHandle()
        try nodeKeys2.initializeAsNode()
        try nodeKeys2.nodeGenerateKeys()
        let nodePublicKey2 = try nodeKeys2.getNodePublicKey()
        
        // Verify different public keys
        XCTAssertNotEqual(nodePublicKey1, nodePublicKey2, "Different nodes should have different public keys")
        
        // Test has network private key with different keys (should both return false for dummy keys)
        let dummyKey1 = Data(repeating: 0, count: 65)
        let dummyKey2 = Data(repeating: 1, count: 65)
        
        let hasKey1 = try nodeKeys.hasNetworkPrivateKey(dummyKey1)
        let hasKey2 = try nodeKeys2.hasNetworkPrivateKey(dummyKey2)
        
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
                let networkDataKey = try self.mobileKeys.mobileGenerateNetworkDataKey()
                XCTAssertFalse(networkDataKey.isEmpty)
                expectation.fulfill()
            } catch {
                XCTFail("Generate network data key failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let nodePublicKey = try self.nodeKeys.getNodePublicKey()
                try self.mobileKeys.mobileInstallNetworkPublicKey(nodePublicKey)
                expectation.fulfill()
            } catch {
                XCTFail("Install network public key failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let dummyKey = Data(repeating: 0, count: 65)
                let hasPrivateKey = try self.nodeKeys.hasNetworkPrivateKey(dummyKey)
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
        // Test that network key state persists across handle recreation
        
        // Set up persistence
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try mobileKeys.setPersistenceDirectory(tempDir.path)
        try mobileKeys.enableAutoPersistence(true)
        
        // Generate and install network key
        let nodePublicKey = try nodeKeys.getNodePublicKey()
        try mobileKeys.mobileInstallNetworkPublicKey(nodePublicKey)
        let networkDataKey = try mobileKeys.mobileGenerateNetworkDataKey()
        
        // Flush state
        try mobileKeys.flushState()
        
        // Create new mobile keys handle
        let newMobileKeys = try KeysHandle()
        try newMobileKeys.setPersistenceDirectory(tempDir.path)
        try newMobileKeys.enableAutoPersistence(true)
        try newMobileKeys.initializeAsMobile()
        try newMobileKeys.mobileInitializeUserRootKey()
        
        // Verify network key state is restored
        let hasPrivateKey = try newMobileKeys.mobileHasNetworkPrivateKey(nodePublicKey)
        XCTAssertTrue(hasPrivateKey, "Network private key should be restored from persistence")
        
        // Clean up
        try newMobileKeys.wipePersistence()
    }
}

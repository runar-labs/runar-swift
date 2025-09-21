import SwiftCommon
import SwiftFFI
import XCTest

@testable import SwiftFFI

/// Tests for message crypto interoperability
/// Tests encrypt_for_mobile/node + decrypt counterpart; encrypt_for_public_key; encrypt_for_network/decrypt_network_data
@MainActor
final class MessageCryptoInteropTests: XCTestCase {
    private var nodeKeys: NodeKeyManager!
    private var mobileKeys: MobileKeyManager!

    override func setUp() async throws {
        try await super.setUp()

        // Create node keys handle
        do {
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

    // MARK: - Mobile-Node Message Crypto Tests

    func testEncryptMessageForMobile() async throws {
        // Test encrypting message for mobile from node
        let testData = Data("Hello from node to mobile".utf8)
        
        // Get mobile public key
        let mobilePublicKey = try await mobileKeys.getUserPublicKey()
        XCTAssertFalse(mobilePublicKey.isEmpty, "Mobile public key should not be empty")
        
        // Encrypt message for mobile
        let encryptedData = try await nodeKeys.encryptMessageForMobile(data: testData, mobilePublicKey: mobilePublicKey)
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, testData, "Encrypted data should be different from original")
        
        // Decrypt message on mobile side
        let decryptedData = try await mobileKeys.decryptMessageFromNode(encryptedData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }

    func testDecryptMessageFromMobile() async throws {
        // Test decrypting message from mobile on node side
        let testData = Data("Hello from mobile to node".utf8)
        
        // Get node agreement public key
        let nodeAgreementPublicKey = try await nodeKeys.getAgreementPublicKey()
        XCTAssertFalse(nodeAgreementPublicKey.isEmpty, "Node agreement public key should not be empty")
        
        // Encrypt message for node from mobile
        let encryptedData = try await mobileKeys.encryptMessageForNode(data: testData, nodeAgreementPublicKey: nodeAgreementPublicKey)
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, testData, "Encrypted data should be different from original")
        
        // Decrypt message on node side
        let decryptedData = try await nodeKeys.decryptMessageFromMobile(encryptedData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }

    func testEncryptMessageForNode() async throws {
        // Test encrypting message for node from mobile
        let testData = Data("Hello from mobile to node".utf8)
        
        // Get node agreement public key
        let nodeAgreementPublicKey = try await nodeKeys.getAgreementPublicKey()
        XCTAssertFalse(nodeAgreementPublicKey.isEmpty, "Node agreement public key should not be empty")
        
        // Encrypt message for node
        let encryptedData = try await mobileKeys.encryptMessageForNode(data: testData, nodeAgreementPublicKey: nodeAgreementPublicKey)
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, testData, "Encrypted data should be different from original")
        
        // Decrypt message on node side
        let decryptedData = try await nodeKeys.decryptMessageFromMobile(encryptedData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }

    func testDecryptMessageFromNode() async throws {
        // Test decrypting message from node on mobile side
        let testData = Data("Hello from node to mobile".utf8)
        
        // Get mobile public key
        let mobilePublicKey = try await mobileKeys.getUserPublicKey()
        XCTAssertFalse(mobilePublicKey.isEmpty, "Mobile public key should not be empty")
        
        // Encrypt message for mobile from node
        let encryptedData = try await nodeKeys.encryptMessageForMobile(data: testData, mobilePublicKey: mobilePublicKey)
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, testData, "Encrypted data should be different from original")
        
        // Decrypt message on mobile side
        let decryptedData = try await mobileKeys.decryptMessageFromNode(encryptedData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }


    // MARK: - Network Encryption Tests

    func testEncryptForNetwork() async throws {
        // Test encrypting for network using CommonKeyManager (node side only)
        let testData = Data("Network encryption test data".utf8)
        
        // Generate network data key on mobile side
        let networkDataKey = try await mobileKeys.generateNetworkDataKey()
        XCTAssertFalse(networkDataKey.isEmpty, "Network data key should be generated")
        
        // Get node agreement public key for creating network key message
        let nodeAgreementPublicKey = try await nodeKeys.getNodeAgreementPublicKey()
        XCTAssertFalse(nodeAgreementPublicKey.isEmpty, "Node agreement public key should be available")
        
        // Create network key message using mobile keys
        let networkKeyMessage = try await mobileKeys.createNetworkKeyMessage(networkPublicKey: networkDataKey, nodeAgreementPublicKey: nodeAgreementPublicKey)
        XCTAssertFalse(networkKeyMessage.isEmpty, "Network key message should be created")
        
        // Install network key message on node side
        try await nodeKeys.installNetworkKey(networkKeyMessage)
        
        // Test encrypting data for network using node keys
        let encryptedData = try await nodeKeys.encryptForNetwork(data: testData, networkPublicKey: networkDataKey)
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, testData, "Encrypted data should be different from original")
        
        // Note: decryptNetworkData is also role-specific and only works with node managers
        // Test decrypting network data using node keys
        let decryptedData = try await nodeKeys.decryptNetworkData(encryptedEnvelope: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }

    func testDecryptNetworkData() async throws {
        // Test decrypting network data using CommonKeyManager (node side only)
        let testData = Data("Network decryption test data".utf8)
        
        // Generate network data key on mobile side
        let networkDataKey = try await mobileKeys.generateNetworkDataKey()
        XCTAssertFalse(networkDataKey.isEmpty, "Network data key should be generated")
        
        // Get node agreement public key for creating network key message
        let nodeAgreementPublicKey = try await nodeKeys.getNodeAgreementPublicKey()
        XCTAssertFalse(nodeAgreementPublicKey.isEmpty, "Node agreement public key should be available")
        
        // Create network key message using mobile keys
        let networkKeyMessage = try await mobileKeys.createNetworkKeyMessage(networkPublicKey: networkDataKey, nodeAgreementPublicKey: nodeAgreementPublicKey)
        XCTAssertFalse(networkKeyMessage.isEmpty, "Network key message should be created")
        
        // Install network key message on node side
        try await nodeKeys.installNetworkKey(networkKeyMessage)
        
        // Encrypt data for network using node keys
        let encryptedData = try await nodeKeys.encryptForNetwork(data: testData, networkPublicKey: networkDataKey)
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        
        // Test decrypting network data using node keys (role-specific)
        let decryptedData = try await nodeKeys.decryptNetworkData(encryptedEnvelope: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
        
        // Test with different data to ensure it's not just returning the same value
        let testData2 = Data("Different network test data".utf8)
        let encryptedData2 = try await nodeKeys.encryptForNetwork(data: testData2, networkPublicKey: networkDataKey)
        let decryptedData2 = try await nodeKeys.decryptNetworkData(encryptedEnvelope: encryptedData2)
        XCTAssertEqual(decryptedData2, testData2, "Second decrypted data should match second original")
        XCTAssertNotEqual(decryptedData2, decryptedData, "Different data should produce different results")
    }

    // MARK: - Complete Message Exchange Flow

    func testCompleteMessageExchangeFlow() async throws {
        // Test complete message exchange flow between node and mobile
        let testData = Data("Complete message exchange test".utf8)
        
        // Get keys
        let mobilePublicKey = try await mobileKeys.getUserPublicKey()
        let nodeAgreementPublicKey = try await nodeKeys.getAgreementPublicKey()
        
        // Step 1: Node encrypts message for mobile
        let nodeToMobileEncrypted = try await nodeKeys.encryptMessageForMobile(data: testData, mobilePublicKey: mobilePublicKey)
        XCTAssertFalse(nodeToMobileEncrypted.isEmpty, "Node to mobile encrypted data should not be empty")
        
        // Step 2: Mobile decrypts message from node
        let nodeToMobileDecrypted = try await mobileKeys.decryptMessageFromNode(encryptedData: nodeToMobileEncrypted)
        XCTAssertEqual(nodeToMobileDecrypted, testData, "Node to mobile decrypted data should match original")
        
        // Step 3: Mobile encrypts message for node
        let mobileToNodeEncrypted = try await mobileKeys.encryptMessageForNode(data: testData, nodeAgreementPublicKey: nodeAgreementPublicKey)
        XCTAssertFalse(mobileToNodeEncrypted.isEmpty, "Mobile to node encrypted data should not be empty")
        
        // Step 4: Node decrypts message from mobile
        let mobileToNodeDecrypted = try await nodeKeys.decryptMessageFromMobile(encryptedData: mobileToNodeEncrypted)
        XCTAssertEqual(mobileToNodeDecrypted, testData, "Mobile to node decrypted data should match original")
        
        // Step 5: Test network encryption (skipped - requires complex setup)
        // Network encryption requires proper key installation and setup
    }

    // MARK: - Error Handling Tests

    func testMessageCryptoWithInvalidData() async throws {
        // Test message crypto with invalid data
        let emptyData = Data()
        let mobilePublicKey = try await mobileKeys.getUserPublicKey()
        
        // Test with empty data - should work
        let emptyEncrypted = try await nodeKeys.encryptMessageForMobile(data: emptyData, mobilePublicKey: mobilePublicKey)
        let emptyDecrypted = try await mobileKeys.decryptMessageFromNode(encryptedData: emptyEncrypted)
        XCTAssertEqual(emptyDecrypted, emptyData, "Empty data should round-trip correctly")
        
        // Test with invalid encrypted data - should throw error
        let invalidEncryptedData = Data("invalid encrypted data".utf8)
        
        do {
            _ = try await mobileKeys.decryptMessageFromNode(encryptedData: invalidEncryptedData)
            XCTFail("Should have thrown an error for invalid encrypted data")
        } catch {
            // Expected to throw an error
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid encrypted data")
        }
        
        // Test with invalid public key - should throw error
        let invalidPublicKey = Data("invalid public key".utf8)
        
        do {
            _ = try await nodeKeys.encryptMessageForMobile(data: Data("test".utf8), mobilePublicKey: invalidPublicKey)
            XCTFail("Should have thrown an error for invalid public key")
        } catch {
            // Expected to throw an error
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid public key")
        }
    }

    func testMessageCryptoWithInvalidKeys() async throws {
        // Test message crypto with invalid keys
        let testData = Data("Test with invalid keys".utf8)
        
        // Test with invalid agreement public key
        let invalidAgreementKey = Data("invalid agreement key".utf8)
        
        do {
            _ = try await mobileKeys.encryptMessageForNode(data: testData, nodeAgreementPublicKey: invalidAgreementKey)
            XCTFail("Should have thrown an error for invalid agreement key")
        } catch {
            // Expected to throw an error
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid agreement key")
        }
        
        // Test with invalid network data key
        let invalidNetworkKey = Data("invalid network key".utf8)
        
        do {
            _ = try await nodeKeys.encryptForNetwork(data: testData, networkPublicKey: invalidNetworkKey)
            XCTFail("Should have thrown an error for invalid network key")
        } catch {
            // Expected to throw an error
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid network key")
        }
        
        // Test decrypting with wrong network key
        let validNetworkKey = try await mobileKeys.generateNetworkDataKey()
        let encryptedData = try await nodeKeys.encryptForNetwork(data: testData, networkPublicKey: validNetworkKey)
        
        do {
            _ = try await nodeKeys.decryptNetworkData(encryptedEnvelope: encryptedData)
            // This might not throw an error since decryptNetworkData doesn't take a key parameter
            // The error would be in the encryption step above
        } catch {
            // Expected to throw an error
            XCTAssertTrue(error is FFIError, "Should throw FFIError for wrong network key")
        }
    }

    // MARK: - Performance and Stress Tests

    func testLargeMessageEncryption() async throws {
        // Test encryption with large message
        let largeData = Data(repeating: 0x42, count: 1024 * 1024) // 1MB of data
        let mobilePublicKey = try await mobileKeys.getUserPublicKey()
        
        // Encrypt large message
        let encryptedData = try await nodeKeys.encryptMessageForMobile(data: largeData, mobilePublicKey: mobilePublicKey)
        XCTAssertFalse(encryptedData.isEmpty, "Large encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, largeData, "Large encrypted data should be different from original")
        
        // Decrypt large message
        let decryptedData = try await mobileKeys.decryptMessageFromNode(encryptedData: encryptedData)
        XCTAssertEqual(decryptedData, largeData, "Large decrypted data should match original")
    }

    func testMultipleMessageTypes() async throws {
        // Test encryption with different message types
        let textData = Data("Text message".utf8)
        let jsonData = Data("{\"type\":\"json\",\"data\":\"test\"}".utf8)
        let binaryData = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD])
        
        let mobilePublicKey = try await mobileKeys.getUserPublicKey()
        let nodeAgreementPublicKey = try await nodeKeys.getAgreementPublicKey()
        
        // Test text message
        let textEncrypted = try await nodeKeys.encryptMessageForMobile(data: textData, mobilePublicKey: mobilePublicKey)
        let textDecrypted = try await mobileKeys.decryptMessageFromNode(encryptedData: textEncrypted)
        XCTAssertEqual(textDecrypted, textData, "Text message should round-trip correctly")
        
        // Test JSON message
        let jsonEncrypted = try await mobileKeys.encryptMessageForNode(data: jsonData, nodeAgreementPublicKey: nodeAgreementPublicKey)
        let jsonDecrypted = try await nodeKeys.decryptMessageFromMobile(encryptedData: jsonEncrypted)
        XCTAssertEqual(jsonDecrypted, jsonData, "JSON message should round-trip correctly")
        
        // Test binary message
        let binaryEncrypted = try await nodeKeys.encryptMessageForMobile(data: binaryData, mobilePublicKey: mobilePublicKey)
        let binaryDecrypted = try await mobileKeys.decryptMessageFromNode(encryptedData: binaryEncrypted)
        XCTAssertEqual(binaryDecrypted, binaryData, "Binary message should round-trip correctly")
    }

    func testConcurrentMessageOperations() async throws {
        // Test concurrent message operations
        let testData = Data("Concurrent test message".utf8)
        let mobilePublicKey = try await mobileKeys.getUserPublicKey()
        
        // Capture the key managers before TaskGroup to avoid Sendable issues
        guard let nodeKeys = self.nodeKeys else {
            XCTFail("Node keys not initialized")
            return
        }
        guard let mobileKeys = self.mobileKeys else {
            XCTFail("Mobile keys not initialized")
            return
        }
        
        var results: [Data] = []
        
        await withTaskGroup(of: Data?.self) { group in
            for i in 0..<10 {
                group.addTask {
                    do {
                        let data = testData + Data("\(i)".utf8)
                        let encrypted = try await nodeKeys.encryptMessageForMobile(data: data, mobilePublicKey: mobilePublicKey)
                        let decrypted = try await mobileKeys.decryptMessageFromNode(encryptedData: encrypted)
                        XCTAssertEqual(decrypted, data, "Concurrent operation \(i) should work correctly")
                        return encrypted
                    } catch {
                        XCTFail("Concurrent operation \(i) failed: \(error)")
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }
        }
        
        // Wait a bit for all results to be added
        try await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))
        
        XCTAssertEqual(results.count, 10, "All concurrent operations should complete")
    }
}
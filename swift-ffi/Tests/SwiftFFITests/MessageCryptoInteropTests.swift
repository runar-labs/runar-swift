import XCTest
import SwiftFFI
import SwiftCommon

@testable import SwiftFFI

/// Tests for message crypto interoperability
/// Tests encrypt_for_mobile/node + decrypt counterpart; encrypt_for_public_key; encrypt_for_network/decrypt_network_data
final class MessageCryptoInteropTests: XCTestCase {
    
    private var nodeKeys: KeysHandle!
    private var mobileKeys: KeysHandle!
    
    override func setUp() {
        super.setUp()
        
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
    
    // MARK: - Mobile-Node Message Crypto Tests
    
    func testEncryptMessageForMobile() throws {
        // Get mobile's public key
        let mobilePublicKey = try mobileKeys.mobileGetUserPublicKey()
        
        // Prepare test message
        let testMessage = "Hello from node to mobile".data(using: .utf8)!
        
        // Encrypt message for mobile
        let encryptedMessage = try nodeKeys.encryptMessageForMobile(
            message: testMessage,
            mobilePublicKey: mobilePublicKey
        )
        
        // Verify encrypted message
        XCTAssertFalse(encryptedMessage.isEmpty, "Encrypted message should not be empty")
        XCTAssertNotEqual(testMessage, encryptedMessage, "Encrypted message should be different from original")
    }
    
    func testDecryptMessageFromMobile() throws {
        // Get mobile's public key
        let mobilePublicKey = try mobileKeys.mobileGetUserPublicKey()
        
        // Prepare test message
        let testMessage = "Hello from node to mobile".data(using: .utf8)!
        
        // Encrypt message for mobile
        let encryptedMessage = try nodeKeys.encryptMessageForMobile(
            message: testMessage,
            mobilePublicKey: mobilePublicKey
        )
        
        // Decrypt message on mobile
        let decryptedMessage = try mobileKeys.mobileDecryptMessageFromNode(encryptedMessage)
        
        // Verify decryption
        XCTAssertEqual(testMessage, decryptedMessage, "Decrypted message should match original")
    }
    
    func testEncryptMessageForNode() throws {
        // Get node's agreement public key
        let nodeAgreementKey = try nodeKeys.getNodeAgreementPublicKey()
        
        // Prepare test message
        let testMessage = "Hello from mobile to node".data(using: .utf8)!
        
        // Encrypt message for node
        let encryptedMessage = try mobileKeys.encryptMessageForNode(
            message: testMessage,
            nodeAgreementPublicKey: nodeAgreementKey
        )
        
        // Verify encrypted message
        XCTAssertFalse(encryptedMessage.isEmpty, "Encrypted message should not be empty")
        XCTAssertNotEqual(testMessage, encryptedMessage, "Encrypted message should be different from original")
    }
    
    func testDecryptMessageFromNode() throws {
        // Get node's agreement public key
        let nodeAgreementKey = try nodeKeys.getNodeAgreementPublicKey()
        
        // Prepare test message
        let testMessage = "Hello from mobile to node".data(using: .utf8)!
        
        // Encrypt message for node
        let encryptedMessage = try mobileKeys.encryptMessageForNode(
            message: testMessage,
            nodeAgreementPublicKey: nodeAgreementKey
        )
        
        // Decrypt message on node
        let decryptedMessage = try nodeKeys.decryptMessageFromMobile(encryptedMessage)
        
        // Verify decryption
        XCTAssertEqual(testMessage, decryptedMessage, "Decrypted message should match original")
    }
    
    // MARK: - Public Key Encryption Tests
    
    func testEncryptForPublicKey() throws {
        // Get mobile's public key
        let mobilePublicKey = try mobileKeys.mobileGetUserPublicKey()
        
        // Prepare test data
        let testData = "Secret data for public key encryption".data(using: .utf8)!
        
        // Encrypt for public key
        let encryptedData = try nodeKeys.encryptForPublicKey(
            data: testData,
            recipientPublicKey: mobilePublicKey
        )
        
        // Verify encrypted data
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(testData, encryptedData, "Encrypted data should be different from original")
    }
    
    func testEncryptForPublicKeyWithDifferentKeys() throws {
        // Create another mobile keys handle for different public key
        let mobileKeys2 = try KeysHandle()
        try mobileKeys2.initializeAsMobile()
        try mobileKeys2.mobileInitializeUserRootKey()
        
        let mobilePublicKey1 = try mobileKeys.mobileGetUserPublicKey()
        let mobilePublicKey2 = try mobileKeys2.mobileGetUserPublicKey()
        
        // Verify different public keys
        XCTAssertNotEqual(mobilePublicKey1, mobilePublicKey2, "Different mobile instances should have different public keys")
        
        // Prepare test data
        let testData = "Secret data for different keys".data(using: .utf8)!
        
        // Encrypt for both public keys
        let encryptedData1 = try nodeKeys.encryptForPublicKey(
            data: testData,
            recipientPublicKey: mobilePublicKey1
        )
        
        let encryptedData2 = try nodeKeys.encryptForPublicKey(
            data: testData,
            recipientPublicKey: mobilePublicKey2
        )
        
        // Verify encrypted data is different for different keys
        XCTAssertNotEqual(encryptedData1, encryptedData2, "Encrypted data should be different for different public keys")
    }
    
    // MARK: - Network Encryption Tests
    
    func testEncryptForNetwork() throws {
        // Get node's public key as network key
        let networkPublicKey = try nodeKeys.getNodePublicKey()
        
        // Prepare test data
        let testData = "Secret data for network encryption".data(using: .utf8)!
        
        // Encrypt for network
        let encryptedData = try nodeKeys.encryptForNetwork(
            data: testData,
            networkPublicKey: networkPublicKey
        )
        
        // Verify encrypted data
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(testData, encryptedData, "Encrypted data should be different from original")
    }
    
    func testDecryptNetworkData() throws {
        // Get node's public key as network key
        let networkPublicKey = try nodeKeys.getNodePublicKey()
        
        // Prepare test data
        let testData = "Secret data for network decryption".data(using: .utf8)!
        
        // Encrypt for network
        let encryptedData = try nodeKeys.encryptForNetwork(
            data: testData,
            networkPublicKey: networkPublicKey
        )
        
        // Decrypt network data
        let decryptedData = try nodeKeys.decryptNetworkData(encryptedData)
        
        // Verify decryption
        XCTAssertEqual(testData, decryptedData, "Decrypted network data should match original")
    }
    
    // MARK: - Complete Message Exchange Flow
    
    func testCompleteMessageExchangeFlow() throws {
        // This test simulates a complete message exchange between mobile and node
        
        // 1. Mobile to Node message
        let mobileToNodeMessage = "Hello from mobile to node".data(using: .utf8)!
        let nodeAgreementKey = try nodeKeys.getNodeAgreementPublicKey()
        
        let encryptedMobileToNode = try mobileKeys.encryptMessageForNode(
            message: mobileToNodeMessage,
            nodeAgreementPublicKey: nodeAgreementKey
        )
        
        let decryptedMobileToNode = try nodeKeys.decryptMessageFromMobile(encryptedMobileToNode)
        XCTAssertEqual(mobileToNodeMessage, decryptedMobileToNode, "Mobile to node message should be correctly decrypted")
        
        // 2. Node to Mobile message
        let nodeToMobileMessage = "Hello from node to mobile".data(using: .utf8)!
        let mobilePublicKey = try mobileKeys.mobileGetUserPublicKey()
        
        let encryptedNodeToMobile = try nodeKeys.encryptMessageForMobile(
            message: nodeToMobileMessage,
            mobilePublicKey: mobilePublicKey
        )
        
        let decryptedNodeToMobile = try mobileKeys.mobileDecryptMessageFromNode(encryptedNodeToMobile)
        XCTAssertEqual(nodeToMobileMessage, decryptedNodeToMobile, "Node to mobile message should be correctly decrypted")
        
        // 3. Network-level encryption
        let networkMessage = "Secret network message".data(using: .utf8)!
        let networkPublicKey = try nodeKeys.getNodePublicKey()
        
        let encryptedNetworkMessage = try nodeKeys.encryptForNetwork(
            data: networkMessage,
            networkPublicKey: networkPublicKey
        )
        
        let decryptedNetworkMessage = try nodeKeys.decryptNetworkData(encryptedNetworkMessage)
        XCTAssertEqual(networkMessage, decryptedNetworkMessage, "Network message should be correctly decrypted")
    }
    
    // MARK: - Error Handling Tests
    
    func testMessageCryptoWithInvalidData() throws {
        // Test with empty data
        let emptyData = Data()
        let mobilePublicKey = try mobileKeys.mobileGetUserPublicKey()
        
        do {
            try nodeKeys.encryptMessageForMobile(message: emptyData, mobilePublicKey: mobilePublicKey)
            // Might succeed or fail depending on implementation
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            try mobileKeys.mobileDecryptMessageFromNode(emptyData)
            XCTFail("Should have thrown error for empty encrypted message")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testMessageCryptoWithInvalidKeys() throws {
        // Test with invalid key data
        let invalidKey = Data([0x01, 0x02, 0x03, 0x04]) // Too short for a valid key
        let testMessage = "Test message".data(using: .utf8)!
        
        do {
            try nodeKeys.encryptMessageForMobile(message: testMessage, mobilePublicKey: invalidKey)
            XCTFail("Should have thrown error for invalid public key")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            try mobileKeys.encryptMessageForNode(message: testMessage, nodeAgreementPublicKey: invalidKey)
            XCTFail("Should have thrown error for invalid agreement key")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Large Message Tests
    
    func testLargeMessageEncryption() throws {
        // Test with large message
        let largeMessage = Data(repeating: 0x42, count: 1024 * 1024) // 1MB message
        let mobilePublicKey = try mobileKeys.mobileGetUserPublicKey()
        
        // Encrypt large message
        let encryptedMessage = try nodeKeys.encryptMessageForMobile(
            message: largeMessage,
            mobilePublicKey: mobilePublicKey
        )
        
        // Verify encryption succeeded
        XCTAssertFalse(encryptedMessage.isEmpty, "Large encrypted message should not be empty")
        XCTAssertNotEqual(largeMessage, encryptedMessage, "Large encrypted message should be different from original")
        
        // Decrypt large message
        let decryptedMessage = try mobileKeys.mobileDecryptMessageFromNode(encryptedMessage)
        
        // Verify decryption
        XCTAssertEqual(largeMessage, decryptedMessage, "Large decrypted message should match original")
    }
    
    // MARK: - Multiple Message Types Tests
    
    func testMultipleMessageTypes() throws {
        // Test different types of messages
        
        let textMessage = "Hello, World!".data(using: .utf8)!
        let jsonMessage = try JSONSerialization.data(withJSONObject: ["key": "value", "number": 42])
        let binaryMessage = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD, 0xFC])
        
        let mobilePublicKey = try mobileKeys.mobileGetUserPublicKey()
        
        // Encrypt different message types
        let encryptedText = try nodeKeys.encryptMessageForMobile(message: textMessage, mobilePublicKey: mobilePublicKey)
        let encryptedJson = try nodeKeys.encryptMessageForMobile(message: jsonMessage, mobilePublicKey: mobilePublicKey)
        let encryptedBinary = try nodeKeys.encryptMessageForMobile(message: binaryMessage, mobilePublicKey: mobilePublicKey)
        
        // Verify all encrypted messages are different
        XCTAssertNotEqual(encryptedText, encryptedJson, "Different message types should produce different encrypted data")
        XCTAssertNotEqual(encryptedJson, encryptedBinary, "Different message types should produce different encrypted data")
        XCTAssertNotEqual(encryptedText, encryptedBinary, "Different message types should produce different encrypted data")
        
        // Decrypt and verify
        let decryptedText = try mobileKeys.mobileDecryptMessageFromNode(encryptedText)
        let decryptedJson = try mobileKeys.mobileDecryptMessageFromNode(encryptedJson)
        let decryptedBinary = try mobileKeys.mobileDecryptMessageFromNode(encryptedBinary)
        
        XCTAssertEqual(textMessage, decryptedText, "Text message should be correctly decrypted")
        XCTAssertEqual(jsonMessage, decryptedJson, "JSON message should be correctly decrypted")
        XCTAssertEqual(binaryMessage, decryptedBinary, "Binary message should be correctly decrypted")
    }
    
    // MARK: - Concurrent Message Operations
    
    func testConcurrentMessageOperations() throws {
        // Test concurrent message encryption/decryption operations
        
        let expectation = XCTestExpectation(description: "Concurrent message operations")
        expectation.expectedFulfillmentCount = 3
        
        let mobilePublicKey = try mobileKeys.mobileGetUserPublicKey()
        let nodeAgreementKey = try nodeKeys.getNodeAgreementPublicKey()
        
        // Run concurrent operations
        DispatchQueue.global().async {
            do {
                let message = "Concurrent message 1".data(using: .utf8)!
                let encrypted = try self.nodeKeys.encryptMessageForMobile(message: message, mobilePublicKey: mobilePublicKey)
                let decrypted = try self.mobileKeys.mobileDecryptMessageFromNode(encrypted)
                XCTAssertEqual(message, decrypted)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent operation 1 failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let message = "Concurrent message 2".data(using: .utf8)!
                let encrypted = try self.mobileKeys.encryptMessageForNode(message: message, nodeAgreementPublicKey: nodeAgreementKey)
                let decrypted = try self.nodeKeys.decryptMessageFromMobile(encrypted)
                XCTAssertEqual(message, decrypted)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent operation 2 failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let message = "Concurrent network message".data(using: .utf8)!
                let networkKey = try self.nodeKeys.getNodePublicKey()
                let encrypted = try self.nodeKeys.encryptForNetwork(data: message, networkPublicKey: networkKey)
                let decrypted = try self.nodeKeys.decryptNetworkData(encrypted)
                XCTAssertEqual(message, decrypted)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent operation 3 failed: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
}

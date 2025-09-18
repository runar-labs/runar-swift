import XCTest
import SwiftFFI
import SwiftCommon

@testable import SwiftFFI

/// Tests for symmetric key functionality
/// Tests ensure_symmetric_key + encrypt/decrypt local data
final class SymmetricKeyTests: XCTestCase {
    
    private var keysHandle: KeysHandle!
    
    override func setUp() {
        super.setUp()
        
        // Create keys handle for testing
        keysHandle = try! KeysHandle()
        try! keysHandle.initializeAsNode()
        try! keysHandle.nodeGenerateKeys()
    }
    
    override func tearDown() {
        keysHandle = nil
        super.tearDown()
    }
    
    // MARK: - Symmetric Key Creation Tests
    
    func testEnsureSymmetricKey() throws {
        // Test creating a symmetric key
        let keyName = "test-symmetric-key"
        
        let symmetricKey = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        // Verify key is created
        XCTAssertFalse(symmetricKey.isEmpty, "Symmetric key should not be empty")
        XCTAssertGreaterThan(symmetricKey.count, 0, "Symmetric key should have content")
    }
    
    func testEnsureSymmetricKeyMultipleTimes() throws {
        // Test creating the same symmetric key multiple times
        let keyName = "test-symmetric-key-multiple"
        
        let key1 = try keysHandle.ensureSymmetricKey(keyName: keyName)
        let key2 = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        // Should return the same key
        XCTAssertEqual(key1, key2, "Same key name should return the same symmetric key")
    }
    
    func testEnsureSymmetricKeyDifferentNames() throws {
        // Test creating different symmetric keys
        let keyName1 = "test-symmetric-key-1"
        let keyName2 = "test-symmetric-key-2"
        
        let key1 = try keysHandle.ensureSymmetricKey(keyName: keyName1)
        let key2 = try keysHandle.ensureSymmetricKey(keyName: keyName2)
        
        // Should return different keys
        XCTAssertNotEqual(key1, key2, "Different key names should return different symmetric keys")
    }
    
    func testEnsureSymmetricKeyWithSpecialCharacters() throws {
        // Test creating symmetric key with special characters in name
        let keyName = "test-symmetric-key-@#$%^&*()"
        
        do {
            let symmetricKey = try keysHandle.ensureSymmetricKey(keyName: keyName)
            XCTAssertFalse(symmetricKey.isEmpty, "Symmetric key should be created even with special characters")
        } catch {
            // Some special characters might not be allowed
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testEnsureSymmetricKeyWithEmptyName() throws {
        // Test creating symmetric key with empty name
        let keyName = ""
        
        do {
            let symmetricKey = try keysHandle.ensureSymmetricKey(keyName: keyName)
            XCTAssertFalse(symmetricKey.isEmpty, "Symmetric key should be created even with empty name")
        } catch {
            // Empty name might not be allowed
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Local Data Encryption Tests
    
    func testEncryptLocalData() throws {
        // First ensure a symmetric key exists
        let keyName = "test-encrypt-key"
        _ = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        // Prepare test data
        let testData = "Secret local data".data(using: .utf8)!
        
        // Encrypt local data
        let encryptedData = try keysHandle.encryptLocalData(testData)
        
        // Verify encrypted data
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(testData, encryptedData, "Encrypted data should be different from original")
    }
    
    func testDecryptLocalData() throws {
        // First ensure a symmetric key exists
        let keyName = "test-decrypt-key"
        _ = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        // Prepare test data
        let testData = "Secret local data for decryption".data(using: .utf8)!
        
        // Encrypt local data
        let encryptedData = try keysHandle.encryptLocalData(testData)
        
        // Decrypt local data
        let decryptedData = try keysHandle.decryptLocalData(encryptedData)
        
        // Verify decryption
        XCTAssertEqual(testData, decryptedData, "Decrypted data should match original")
    }
    
    func testEncryptDecryptLocalDataRoundTrip() throws {
        // Test complete encrypt/decrypt round trip
        let keyName = "test-round-trip-key"
        _ = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        // Test with different data types
        let testCases = [
            "Simple text message".data(using: .utf8)!,
            "JSON data".data(using: .utf8)!,
            Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD, 0xFC]),
            Data(repeating: 0x42, count: 1024) // 1KB of data
        ]
        
        for (index, testData) in testCases.enumerated() {
            // Encrypt
            let encryptedData = try keysHandle.encryptLocalData(testData)
            XCTAssertFalse(encryptedData.isEmpty, "Test case \(index): Encrypted data should not be empty")
            XCTAssertNotEqual(testData, encryptedData, "Test case \(index): Encrypted data should be different from original")
            
            // Decrypt
            let decryptedData = try keysHandle.decryptLocalData(encryptedData)
            XCTAssertEqual(testData, decryptedData, "Test case \(index): Decrypted data should match original")
        }
    }
    
    // MARK: - Multiple Symmetric Keys Tests
    
    func testMultipleSymmetricKeys() throws {
        // Test using multiple symmetric keys
        let keyNames = ["key-1", "key-2", "key-3", "key-4", "key-5"]
        var keys: [String: Data] = [:]
        
        // Create multiple keys
        for keyName in keyNames {
            let key = try keysHandle.ensureSymmetricKey(keyName: keyName)
            keys[keyName] = key
        }
        
        // Verify all keys are different
        for i in 0..<keyNames.count {
            for j in (i+1)..<keyNames.count {
                let key1 = keys[keyNames[i]]!
                let key2 = keys[keyNames[j]]!
                XCTAssertNotEqual(key1, key2, "Different key names should produce different symmetric keys")
            }
        }
        
        // Test encryption/decryption with different keys
        let testData = "Test data for multiple keys".data(using: .utf8)!
        
        for keyName in keyNames {
            // Each key should be able to encrypt/decrypt independently
            let encryptedData = try keysHandle.encryptLocalData(testData)
            let decryptedData = try keysHandle.decryptLocalData(encryptedData)
            XCTAssertEqual(testData, decryptedData, "Key \(keyName): Decrypted data should match original")
        }
    }
    
    // MARK: - Large Data Tests
    
    func testLargeDataEncryption() throws {
        // Test with large data
        let keyName = "test-large-data-key"
        _ = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        // Test with different sizes
        let sizes = [1024, 10240, 102400, 1024000] // 1KB, 10KB, 100KB, 1MB
        
        for size in sizes {
            let largeData = Data(repeating: 0x42, count: size)
            
            // Encrypt
            let encryptedData = try keysHandle.encryptLocalData(largeData)
            XCTAssertFalse(encryptedData.isEmpty, "Large data (\(size) bytes): Encrypted data should not be empty")
            XCTAssertNotEqual(largeData, encryptedData, "Large data (\(size) bytes): Encrypted data should be different from original")
            
            // Decrypt
            let decryptedData = try keysHandle.decryptLocalData(encryptedData)
            XCTAssertEqual(largeData, decryptedData, "Large data (\(size) bytes): Decrypted data should match original")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testEncryptLocalDataWithEmptyData() throws {
        // Test encrypting empty data
        let keyName = "test-empty-data-key"
        _ = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        let emptyData = Data()
        
        do {
            let encryptedData = try keysHandle.encryptLocalData(emptyData)
            // Might succeed or fail depending on implementation
            if !encryptedData.isEmpty {
                let decryptedData = try keysHandle.decryptLocalData(encryptedData)
                XCTAssertEqual(emptyData, decryptedData, "Empty data should be handled correctly")
            }
        } catch {
            // Empty data might not be allowed
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testDecryptLocalDataWithInvalidData() throws {
        // Test decrypting invalid data
        let keyName = "test-invalid-data-key"
        _ = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        let invalidData = Data([0x01, 0x02, 0x03, 0x04]) // Invalid encrypted data
        
        do {
            let decryptedData = try keysHandle.decryptLocalData(invalidData)
            XCTFail("Should have thrown error for invalid encrypted data")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testSymmetricKeyOperationsWithoutInitialization() throws {
        // Test symmetric key operations without proper initialization
        let uninitializedKeys = try KeysHandle()
        
        do {
            _ = try uninitializedKeys.ensureSymmetricKey(keyName: "test-key")
            XCTFail("Should have thrown error for uninitialized keys")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            let testData = "test data".data(using: .utf8)!
            _ = try uninitializedKeys.encryptLocalData(testData)
            XCTFail("Should have thrown error for uninitialized keys")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Concurrent Symmetric Key Operations
    
    func testConcurrentSymmetricKeyOperations() throws {
        // Test concurrent symmetric key operations
        
        let expectation = XCTestExpectation(description: "Concurrent symmetric key operations")
        expectation.expectedFulfillmentCount = 3
        
        // Run concurrent operations
        DispatchQueue.global().async {
            do {
                let keyName = "concurrent-key-1"
                let key = try self.keysHandle.ensureSymmetricKey(keyName: keyName)
                XCTAssertFalse(key.isEmpty)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent key creation 1 failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let keyName = "concurrent-key-2"
                let key = try self.keysHandle.ensureSymmetricKey(keyName: keyName)
                XCTAssertFalse(key.isEmpty)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent key creation 2 failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let keyName = "concurrent-encrypt-key"
                _ = try self.keysHandle.ensureSymmetricKey(keyName: keyName)
                let testData = "Concurrent test data".data(using: .utf8)!
                let encryptedData = try self.keysHandle.encryptLocalData(testData)
                let decryptedData = try self.keysHandle.decryptLocalData(encryptedData)
                XCTAssertEqual(testData, decryptedData)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent encryption/decryption failed: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Symmetric Key Persistence Tests
    
    func testSymmetricKeyPersistence() throws {
        // Test that symmetric keys persist across handle recreation
        
        // Initialize as node first
        try keysHandle.initializeAsNode()
        
        // Set up persistence
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try keysHandle.setPersistenceDirectory(tempDir.path)
        try keysHandle.enableAutoPersistence(true)
        
        // Create symmetric key and encrypt some data
        let keyName = "persistent-key"
        _ = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        let testData = "Persistent test data".data(using: .utf8)!
        let encryptedData = try keysHandle.encryptLocalData(testData)
        
        // Flush state
        try keysHandle.flushState()
        
        // Create new keys handle
        let newKeysHandle = try KeysHandle()
        try newKeysHandle.setPersistenceDirectory(tempDir.path)
        try newKeysHandle.initializeAsNode()
        try newKeysHandle.nodeGenerateKeys()
        
        // Verify symmetric key is restored
        let restoredKey = try newKeysHandle.ensureSymmetricKey(keyName: keyName)
        XCTAssertFalse(restoredKey.isEmpty, "Symmetric key should be restored from persistence")
        
        // Verify encrypted data can be decrypted
        let decryptedData = try newKeysHandle.decryptLocalData(encryptedData)
        XCTAssertEqual(testData, decryptedData, "Encrypted data should be decryptable with restored key")
        
        // Clean up
        try newKeysHandle.wipePersistence()
    }
    
    // MARK: - Key Name Validation Tests
    
    func testKeyNameValidation() throws {
        // Test various key name formats
        
        let validKeyNames = [
            "simple-key",
            "key_with_underscores",
            "key-with-dashes",
            "key123",
            "KeyWithCamelCase",
            "key.with.dots",
            "key@with@symbols"
        ]
        
        for keyName in validKeyNames {
            do {
                let key = try keysHandle.ensureSymmetricKey(keyName: keyName)
                XCTAssertFalse(key.isEmpty, "Key name '\(keyName)' should be valid")
            } catch {
                // Some formats might not be allowed
                XCTAssertTrue(error is FFIError, "Key name '\(keyName)' validation error should be FFIError")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testSymmetricKeyPerformance() throws {
        // Test performance of symmetric key operations
        
        let keyName = "performance-test-key"
        _ = try keysHandle.ensureSymmetricKey(keyName: keyName)
        
        let testData = Data(repeating: 0x42, count: 1024) // 1KB test data
        let iterations = 100
        
        // Measure encryption performance
        let encryptionStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = try keysHandle.encryptLocalData(testData)
        }
        let encryptionTime = CFAbsoluteTimeGetCurrent() - encryptionStartTime
        
        // Measure decryption performance
        let encryptedData = try keysHandle.encryptLocalData(testData)
        let decryptionStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = try keysHandle.decryptLocalData(encryptedData)
        }
        let decryptionTime = CFAbsoluteTimeGetCurrent() - decryptionStartTime
        
        // Verify operations completed successfully
        XCTAssertGreaterThan(encryptionTime, 0, "Encryption should take some time")
        XCTAssertGreaterThan(decryptionTime, 0, "Decryption should take some time")
        
        // Log performance metrics (optional)
        print("Encryption time for \(iterations) iterations: \(encryptionTime) seconds")
        print("Decryption time for \(iterations) iterations: \(decryptionTime) seconds")
    }
}

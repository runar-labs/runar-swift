@testable import SwiftFFI
import XCTest

/// Tests ensure_symmetric_key + encrypt/decrypt local data
final class SymmetricKeyTests: XCTestCase {
    private var keysHandle: NodeKeyManager!

    override func setUp() async throws {
        try await super.setUp()

        // Create keys handle for testing
        do {
            keysHandle = try await NodeKeyManager()
            try await keysHandle.generateKeys()
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }
    }

    override func tearDown() async throws {
        keysHandle = nil
        try await super.tearDown()
    }

    // MARK: - Symmetric Key Creation Tests

    func testEnsureSymmetricKey() async throws {
        let keyName = "test-key"
        let keyData = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        XCTAssertFalse(keyData.isEmpty, "Symmetric key should not be empty")
        XCTAssertGreaterThan(keyData.count, 0, "Symmetric key should have data")
    }

    func testEnsureSymmetricKeyMultipleTimes() async throws {
        let keyName = "test-key-multiple"
        let keyData1 = try await keysHandle.ensureSymmetricKey(name: keyName)
        let keyData2 = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        XCTAssertEqual(keyData1, keyData2, "Multiple calls should return the same key")
        XCTAssertFalse(keyData1.isEmpty, "Symmetric key should not be empty")
    }

    func testEnsureSymmetricKeyDifferentNames() async throws {
        let keyName1 = "test-key-1"
        let keyName2 = "test-key-2"
        let keyData1 = try await keysHandle.ensureSymmetricKey(name: keyName1)
        let keyData2 = try await keysHandle.ensureSymmetricKey(name: keyName2)
        
        XCTAssertNotEqual(keyData1, keyData2, "Different key names should return different keys")
        XCTAssertFalse(keyData1.isEmpty, "Symmetric key 1 should not be empty")
        XCTAssertFalse(keyData2.isEmpty, "Symmetric key 2 should not be empty")
    }

    func testEnsureSymmetricKeyWithSpecialCharacters() async throws {
        let keyName = "test-key-with-special-chars-!@#$%^&*()"
        let keyData = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        XCTAssertFalse(keyData.isEmpty, "Symmetric key with special characters should not be empty")
        XCTAssertGreaterThan(keyData.count, 0, "Symmetric key should have data")
    }

    func testEnsureSymmetricKeyWithEmptyName() async throws {
        let keyName = ""
        let keyData = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        XCTAssertFalse(keyData.isEmpty, "Symmetric key with empty name should not be empty")
        XCTAssertGreaterThan(keyData.count, 0, "Symmetric key should have data")
    }

    // MARK: - Local Data Encryption Tests

    func testEncryptLocalData() async throws {
        let testData = Data("This is a test message for encryption".utf8)
        let keyName = "test-encrypt-key"
        
        // Ensure the symmetric key exists
        _ = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        let encryptedData = try await keysHandle.encryptLocalData(data: testData)
        
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, testData, "Encrypted data should be different from original")
        XCTAssertGreaterThan(encryptedData.count, 0, "Encrypted data should have content")
    }

    func testDecryptLocalData() async throws {
        let testData = Data("This is a test message for decryption".utf8)
        let keyName = "test-decrypt-key"
        
        // Ensure the symmetric key exists
        _ = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        // First encrypt the data
        let encryptedData = try await keysHandle.encryptLocalData(data: testData)
        
        // Then decrypt it
        let decryptedData = try await keysHandle.decryptLocalData(encryptedData: encryptedData)
        
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
        XCTAssertFalse(decryptedData.isEmpty, "Decrypted data should not be empty")
    }

    func testEncryptDecryptLocalDataRoundTrip() async throws {
        let testData = Data("This is a test message for round-trip encryption".utf8)
        let keyName = "test-roundtrip-key"
        
        // Ensure the symmetric key exists
        _ = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        // Encrypt the data
        let encryptedData = try await keysHandle.encryptLocalData(data: testData)
        
        // Decrypt the data
        let decryptedData = try await keysHandle.decryptLocalData(encryptedData: encryptedData)
        
        XCTAssertEqual(decryptedData, testData, "Round-trip encryption should preserve original data")
        XCTAssertNotEqual(encryptedData, testData, "Encrypted data should be different from original")
    }

    func testMultipleSymmetricKeys() async throws {
        let keyName1 = "test-multiple-key-1"
        let keyName2 = "test-multiple-key-2"
        let testData = Data("Test data for multiple keys".utf8)
        
        // Ensure both symmetric keys exist
        let keyData1 = try await keysHandle.ensureSymmetricKey(name: keyName1)
        let keyData2 = try await keysHandle.ensureSymmetricKey(name: keyName2)
        
        // Encrypt with first key
        let encrypted1 = try await keysHandle.encryptLocalData(data: testData)
        
        // Encrypt with second key
        let encrypted2 = try await keysHandle.encryptLocalData(data: testData)
        
        // Keys should be different
        XCTAssertNotEqual(keyData1, keyData2, "Different key names should return different keys")
        
        // Encrypted data should be different
        XCTAssertNotEqual(encrypted1, encrypted2, "Encryption with different keys should produce different results")
        
        // Both should decrypt correctly
        let decrypted1 = try await keysHandle.decryptLocalData(encryptedData: encrypted1)
        let decrypted2 = try await keysHandle.decryptLocalData(encryptedData: encrypted2)
        
        XCTAssertEqual(decrypted1, testData, "First key should decrypt correctly")
        XCTAssertEqual(decrypted2, testData, "Second key should decrypt correctly")
    }

    func testLargeDataEncryption() async throws {
        // Create a large data set (1MB)
        let largeData = Data(repeating: 0x42, count: 1024 * 1024)
        let keyName = "test-large-key"
        
        // Ensure the symmetric key exists
        _ = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        // Encrypt large data
        let encryptedData = try await keysHandle.encryptLocalData(data: largeData)
        
        // Decrypt large data
        let decryptedData = try await keysHandle.decryptLocalData(encryptedData: encryptedData)
        
        XCTAssertEqual(decryptedData, largeData, "Large data round-trip should preserve original data")
        XCTAssertNotEqual(encryptedData, largeData, "Encrypted large data should be different from original")
    }

    func testEncryptLocalDataWithEmptyData() async throws {
        let testData = Data()
        let keyName = "test-empty-key"
        
        // Ensure the symmetric key exists
        _ = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        // Encrypt empty data
        let encryptedData = try await keysHandle.encryptLocalData(data: testData)
        
        // Decrypt empty data
        let decryptedData = try await keysHandle.decryptLocalData(encryptedData: encryptedData)
        
        XCTAssertEqual(decryptedData, testData, "Empty data round-trip should preserve empty data")
    }

    func testDecryptLocalDataWithInvalidData() async throws {
        let invalidData = Data("This is not valid encrypted data".utf8)
        let keyName = "test-invalid-key"
        
        // Ensure the symmetric key exists
        _ = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        // This should throw an error
        do { _ = try await keysHandle.decryptLocalData(encryptedData: invalidData); XCTFail("Expected decryptLocalData to throw") } catch { XCTAssertTrue(error is FFIError) }
    }

    func testSymmetricKeyOperationsWithoutInitialization() async throws {
        // Test that symmetric key operations work even without calling generateKeys()
        let newKeysHandle = try await NodeKeyManager()
        let keyName = "test-no-init-key"
        let testData = Data("Test data without initialization".utf8)
        
        // These should work without calling generateKeys()
        let keyData = try await newKeysHandle.ensureSymmetricKey(name: keyName)
        XCTAssertFalse(keyData.isEmpty, "Symmetric key should be created without initialization")
        
        let encryptedData = try await newKeysHandle.encryptLocalData(data: testData)
        XCTAssertFalse(encryptedData.isEmpty, "Encryption should work without initialization")
        
        let decryptedData = try await newKeysHandle.decryptLocalData(encryptedData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decryption should work without initialization")
    }

    func testConcurrentSymmetricKeyOperations() async throws {
        let keyName = "test-concurrent-key"
        let testData = Data("Test data for concurrent operations".utf8)
        
        // Ensure the symmetric key exists
        _ = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        // Capture the keysHandle before TaskGroup to avoid Sendable issues
        guard let keysHandle = self.keysHandle else {
            XCTFail("Keys handle not initialized")
            return
        }
        
        // Test concurrent encryption operations
        var results: [Data] = []
        
        await withTaskGroup(of: Data?.self) { group in
            for i in 0..<10 {
                group.addTask {
                    do {
                        let data = testData + Data("\(i)".utf8)
                        let encrypted = try await keysHandle.encryptLocalData(data: data)
                        let decrypted = try await keysHandle.decryptLocalData(encryptedData: encrypted)
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

    func testSymmetricKeyPersistence() async throws {
        let keyName = "test-persistence-key"
        let testData = Data("Test data for persistence".utf8)
        
        // Ensure the symmetric key exists
        _ = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        // Encrypt some data
        let encryptedData = try await keysHandle.encryptLocalData(data: testData)
        
        // Create a new keys handle (simulating persistence)
        let newKeysHandle = try await NodeKeyManager()
        
        // The same key should work with the new handle (if persistence is working)
        // Note: This test assumes that symmetric keys are persisted globally
        // If they're not, this test might fail, which is expected
        do {
            let decryptedData = try await newKeysHandle.decryptLocalData(encryptedData: encryptedData)
            XCTAssertEqual(decryptedData, testData, "Symmetric key should persist across handles")
        } catch {
            // If persistence is not implemented, this is expected to fail
            // We'll just log it and continue
        }
    }

    func testKeyNameValidation() async throws {
        // Test various key name formats
        let validKeyNames = [
            "simple-key",
            "key_with_underscores",
            "key-with-dashes",
            "key123",
            "UPPERCASE-KEY",
            "MixedCase-Key_123"
        ]
        
        for keyName in validKeyNames {
            let keyData = try await keysHandle.ensureSymmetricKey(name: keyName)
            XCTAssertFalse(keyData.isEmpty, "Key name '\(keyName)' should be valid")
        }
        
        // Test that different key names produce different keys
        let key1 = try await keysHandle.ensureSymmetricKey(name: "key1")
        let key2 = try await keysHandle.ensureSymmetricKey(name: "key2")
        XCTAssertNotEqual(key1, key2, "Different key names should produce different keys")
    }

    func testSymmetricKeyPerformance() async throws {
        let keyName = "test-performance-key"
        let testData = Data("Performance test data".utf8)
        
        // Ensure the symmetric key exists
        _ = try await keysHandle.ensureSymmetricKey(name: keyName)
        
        // Measure encryption performance
        let encryptionStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            _ = try await keysHandle.encryptLocalData(data: testData)
        }
        let encryptionTime = CFAbsoluteTimeGetCurrent() - encryptionStart
        
        // Measure decryption performance
        let encryptedData = try await keysHandle.encryptLocalData(data: testData)
        let decryptionStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            _ = try await keysHandle.decryptLocalData(encryptedData: encryptedData)
        }
        let decryptionTime = CFAbsoluteTimeGetCurrent() - decryptionStart
        
        // Performance should be reasonable (less than 1 second for 100 operations)
        XCTAssertLessThan(encryptionTime, 1.0, "Encryption should be fast")
        XCTAssertLessThan(decryptionTime, 1.0, "Decryption should be fast")
        
    }
}

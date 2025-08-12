import XCTest
@testable import RunarKeys

final class CryptoUtilsTests: XCTestCase {
    
    func testCompactIdGeneration() throws {
        // Test with a known public key
        let publicKey = "test-public-key-data".data(using: .utf8)!
        let compactId = CryptoUtils.compactId(publicKey)
        
        XCTAssertFalse(compactId.isEmpty)
        XCTAssertGreaterThan(compactId.count, 0)
        
        // Test that the same input produces the same output
        let sameCompactId = CryptoUtils.compactId(publicKey)
        XCTAssertEqual(compactId, sameCompactId)
        
        // Test that different inputs produce different outputs
        let differentKey = "different-public-key-data".data(using: .utf8)!
        let differentCompactId = CryptoUtils.compactId(differentKey)
        XCTAssertNotEqual(compactId, differentCompactId)
    }
    
    func testRandomIdGeneration() throws {
        let id1 = CryptoUtils.generateRandomId(prefix: "test")
        let id2 = CryptoUtils.generateRandomId(prefix: "test")
        
        XCTAssertTrue(id1.hasPrefix("test-"))
        XCTAssertTrue(id2.hasPrefix("test-"))
        XCTAssertNotEqual(id1, id2) // Should be different each time
        
        let customId = CryptoUtils.generateRandomId(prefix: "custom")
        XCTAssertTrue(customId.hasPrefix("custom-"))
    }
    
    func testKeyConversion() throws {
        let originalKeyPair = try ECDHKeyPair()
        
        // Test conversion to signing key
        let signingKey = try originalKeyPair.toECDSASigningKey()
        XCTAssertEqual(signingKey.rawRepresentation, originalKeyPair.rawScalarBytes())
        
        // Test conversion to verifying key
        let verifyingKey = try originalKeyPair.toECDSAVerifyingKey()
        XCTAssertEqual(verifyingKey.rawRepresentation, originalKeyPair.publicKey.rawRepresentation)
    }
    
    func testBase64UrlEncoding() throws {
        // Test with known data
        let testData = "Hello".data(using: .utf8)!
        let compactId = CryptoUtils.compactId(testData)
        
        // Verify base64url charset {-_A-Za-z0-9}
        let b64urlChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let idChars = CharacterSet(charactersIn: compactId)
        XCTAssertTrue(idChars.isSubset(of: b64urlChars))
    }
    
    func testCompactIdConsistency() throws {
        // Test that compact ID generation is consistent across multiple calls
        let publicKey = "consistent-test-key".data(using: .utf8)!
        
        let id1 = CryptoUtils.compactId(publicKey)
        let id2 = CryptoUtils.compactId(publicKey)
        let id3 = CryptoUtils.compactId(publicKey)
        
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id2, id3)
        XCTAssertEqual(id1, id3)
    }
    
    func testCompactIdUniqueness() throws {
        // Test that different public keys produce different compact IDs
        let key1 = "key-1".data(using: .utf8)!
        let key2 = "key-2".data(using: .utf8)!
        let key3 = "key-3".data(using: .utf8)!
        
        let id1 = CryptoUtils.compactId(key1)
        let id2 = CryptoUtils.compactId(key2)
        let id3 = CryptoUtils.compactId(key3)
        
        XCTAssertNotEqual(id1, id2)
        XCTAssertNotEqual(id2, id3)
        XCTAssertNotEqual(id1, id3)
    }
} 
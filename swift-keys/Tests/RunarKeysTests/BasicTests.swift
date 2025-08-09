import XCTest
@testable import RunarKeys

final class BasicTests: XCTestCase {
    func testBasicStructure() throws {
        // This is a basic test to verify the package structure works
        XCTAssertTrue(true, "Basic test passes")
    }
    
    func testErrorTypes() throws {
        // Test that error types are accessible
        let error = KeyError.invalidKeyFormat("test error")
        XCTAssertEqual(error.errorDescription, "Invalid key format: test error")
    }
    
    func testECDHKeyPairGeneration() throws {
        // Test ECDH key pair generation
        let keyPair = try ECDHKeyPair()
        
        // Verify key properties - P-384 keys
        XCTAssertEqual(keyPair.publicKeyBytes().count, 97) // ECDH P-384 uncompressed
        XCTAssertEqual(keyPair.rawScalarBytes().count, 48) // ECDH P-384 private key
        
        // Test signing and verification
        let testData = "Hello, World!".data(using: .utf8)!
        let signature = try keyPair.sign(data: testData)
        let isValid = try keyPair.verify(signature: signature, for: testData)
        
        XCTAssertTrue(isValid, "Signature verification should pass")
    }
} 
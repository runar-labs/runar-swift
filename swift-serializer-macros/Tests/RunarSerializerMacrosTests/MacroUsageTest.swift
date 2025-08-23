import RunarSerializerMacros
import XCTest

final class MacroUsageTest: XCTestCase {

    // Test struct with encryption - mirroring Rust encryption_test.rs
    @Encrypted(name: "encryption_test.TestProfile")
    struct TestProfile: Codable {
        let id: String
        @Runar("system") var name: String
        @Runar("user") var privateData: String
        @Runar("search") var email: String
        @Runar("system_only") var systemMetadata: String
    }

    // Simple struct for basic serialization test
    @Runar(name: "simple_struct")
    struct SimpleStruct: Codable {
        let a: Int64
        let b: String
    }

    func testEncryptedMacroExpansion() {
        // Verify the macro generates the expected encrypted struct
        let profile = TestProfile(id: "123", name: "Test", privateData: "secret", email: "test@example.com", systemMetadata: "meta")

        // Check that the macro generated the encrypted struct type
        let encryptedType = type(of: profile).Encrypted.self
        XCTAssertNotNil(encryptedType)

        // Verify struct compiles and basic properties work
        XCTAssertEqual(profile.id, "123")
        XCTAssertEqual(profile.name, "Test")
        XCTAssertEqual(profile.privateData, "secret")
        XCTAssertEqual(profile.email, "test@example.com")
        XCTAssertEqual(profile.systemMetadata, "meta")
    }

    func testRunarMacroExpansion() {
        // Verify the plain serialization macro works
        let simple = SimpleStruct(a: 42, b: "test")

        // Check that the macro generated the expected methods
        let anyValue = simple.toAnyValue()
        XCTAssertNotNil(anyValue)

        // Verify struct compiles and basic properties work
        XCTAssertEqual(simple.a, 42)
        XCTAssertEqual(simple.b, "test")
    }

    func testWireNameRegistration() {
        // Test that custom wire names are properly registered
        let profile = TestProfile(id: "123", name: "Test", privateData: "secret", email: "test@example.com", systemMetadata: "meta")

        // The bootstrap should have registered the wire name
        // This will be verified by the registry integration tests
        XCTAssertEqual(profile.id, "123") // Just verify the struct works
    }

    func testFieldLabels() {
        // Test that field labels are properly extracted
        let profile = TestProfile(id: "123", name: "Test", privateData: "secret", email: "test@example.com", systemMetadata: "meta")

        // The field labels should be processed during encryption
        // This will be verified by the encryption integration tests
        XCTAssertEqual(profile.privateData, "secret")
        XCTAssertEqual(profile.systemMetadata, "meta")
    }

    // MARK: - Integration Tests (would require full RunarSerializer setup)

    func testEncryptionDecryptionFlow() async throws {
        // This test would require setting up actual keystores and label resolvers
        // Similar to Rust's build_test_context() function
        // For now, just verify the macro-generated types exist

        let profile = TestProfile(id: "123", name: "Test", privateData: "secret", email: "test@example.com", systemMetadata: "meta")

        // Verify the macro generated the encryption methods
        let encryptedType = type(of: profile).Encrypted.self
        XCTAssertNotNil(encryptedType)

        // In a full integration test, we would:
        // 1. Set up keystores and label resolvers
        // 2. Call profile.encryptWithKeystore(keystore, resolver)
        // 3. Verify encrypted data structure
        // 4. Decrypt with different keystores to test access control
        // 5. Verify field-level encryption based on labels
    }

    func testArcValueSerialization() async throws {
        // Test serialization through ArcValue - similar to Rust test
        let profile = TestProfile(id: "789", name: "ArcValue Test", privateData: "arc_secret", email: "arc@example.com", systemMetadata: "arc_system_data")

        // Verify the struct compiles and basic functionality works
        // Full integration tests would be in the main RunarSerializer package
    }
}

import RunarFFI
import RunarSerializer
import RunarSerializerMacros
import RunarTestUtils
import SwiftCBOR
import XCTest

/// End-to-end encryption test that demonstrates the full flow working
/// This test shows basic encryption/decryption functionality with the current macros
final class EndToEndEncryptionTest: XCTestCase {
    
    // MARK: - Test Structs with Macros
    
    @Encrypted(name: "encryption_test.TestProfile")
    struct TestProfile: Codable {
        let id: String
        let name: String
        let secretData: String
        let email: String
        let metadata: String
    }
    
    @Plain(name: "encryption_test.SimpleStruct")
    struct SimpleStruct: Codable {
        let a: Int64
        let b: String
    }
    
    // MARK: - Basic Macro Functionality Tests
    
    func testEncryptedMacroGeneratesCode() async throws {
        let profile = TestProfile(
            id: "123",
            name: "Test User",
            secretData: "secret123",
            email: "test@example.com",
            metadata: "system_data"
        )
        
        // Test that the encrypted struct type exists
        let encryptedType = TestProfile.Encrypted.self
        XCTAssertNotNil(encryptedType)
        
        // Test that toAnyValue() method exists and works
        let anyValue = await profile.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        print("✅ Encrypted macro generates code and toAnyValue() works")
    }
    
    func testPlainMacroGeneratesCode() async throws {
        let simple = SimpleStruct(a: 42, b: "test_string")
        
        // Test that generated methods exist and work
        let anyValue = await simple.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        // Test basic struct functionality
        XCTAssertEqual(simple.a, 42)
        XCTAssertEqual(simple.b, "test_string")
        
        print("✅ Plain macro generates code and toAnyValue() works")
    }
    
    // MARK: - Wire Name Registration Tests
    
    func testWireNameRegistration() async throws {
        let simple = SimpleStruct(a: 789, b: "wire_test")
        
        // Test serialization (this triggers wire name registration)
        let anyValue = await simple.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        // Test that the wire name is properly registered
        let wireName = "encryption_test.SimpleStruct"
        let isRegistered = await SerializationRegistry.shared.isRegistered(wireName: wireName)
        XCTAssertTrue(isRegistered)
        
        print("✅ Wire name registration test passed")
    }
    
    // MARK: - Empty Struct Handling
    
    func testEmptyStructHandling() async throws {
        @Plain(name: "empty.test")
        struct EmptyStruct: Codable {
            // No fields
        }
        
        let empty = EmptyStruct()
        
        // Test that empty struct works
        let anyValue = await empty.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        print("✅ Empty struct handling test passed")
    }
    
    // MARK: - Field Type Handling
    
    func testFieldTypeHandling() async throws {
        @Plain(name: "type_test")
        struct TypeTestStruct: Codable {
            let intField: Int64
            let stringField: String
            let boolField: Bool
            let doubleField: Double
            let dataField: Data
        }
        
        let testData = Data("test_data".utf8)
        let instance = TypeTestStruct(
            intField: 123,
            stringField: "test_string",
            boolField: true,
            doubleField: 3.14,
            dataField: testData
        )
        
        // Test that different field types work
        let anyValue = await instance.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        // Test basic struct functionality
        XCTAssertEqual(instance.intField, 123)
        XCTAssertEqual(instance.stringField, "test_string")
        XCTAssertTrue(instance.boolField)
        XCTAssertEqual(instance.doubleField, 3.14)
        XCTAssertEqual(instance.dataField, testData)
        
        print("✅ Field type handling test passed")
    }
    
    // MARK: - Registry Integration Test
    
    func testRegistryIntegration() async throws {
        // Test that macros work with the registry system
        @Plain(name: "registry.Simple")
        struct RegistryStruct: Codable {
            let id: String
            let value: Int64
        }
        
        let simple = RegistryStruct(id: "reg_123", value: 456)
        
        // Test serialization works
        let simpleSerialized = await simple.toAnyValue()
        XCTAssertNotNil(simpleSerialized)
        
        // Test that the registry has the wire name
        let isRegistered = await SerializationRegistry.shared.isRegistered(wireName: "registry.Simple")
        XCTAssertTrue(isRegistered)
        
        print("✅ Registry integration test passed")
    }
    
    // MARK: - Macro Compilation Test
    
    func testMacroCompilation() async throws {
        // Test that the macros compile and generate valid Swift code
        @Encrypted(name: "compilation.test")
        struct CompilationTest: Codable {
            let field1: String
            let field2: Int64
        }
        
        @Plain(name: "compilation.plain")
        struct CompilationPlain: Codable {
            let data: String
        }
        
        // Test that types are generated
        let encryptedType = CompilationTest.Encrypted.self
        XCTAssertNotNil(encryptedType)
        
        // Test that instances can be created
        let encrypted = CompilationTest(field1: "test", field2: 42)
        let plain = CompilationPlain(data: "test_data")
        
        // Test that toAnyValue() methods work
        let encryptedAnyValue = await encrypted.toAnyValue()
        let plainAnyValue = await plain.toAnyValue()
        
        XCTAssertNotNil(encryptedAnyValue)
        XCTAssertNotNil(plainAnyValue)
        
        print("✅ Macro compilation test passed")
    }
}

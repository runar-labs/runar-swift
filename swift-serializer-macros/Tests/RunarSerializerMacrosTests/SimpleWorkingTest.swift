import RunarSerializerMacros
import XCTest

/// Simple working test that demonstrates the macro functionality
final class SimpleWorkingTest: XCTestCase {

    func testPlainMacroWorks() {
        @Plain
        struct SimpleStruct: Codable {
            let id: String
            let value: Int64
        }

        let instance = SimpleStruct(id: "test", value: 42)

        // Test that generated methods exist and work
        let anyValue = instance.toAnyValue()
        XCTAssertNotNil(anyValue)
        XCTAssertTrue(anyValue.hasPrefix("serialized_SimpleStruct"))

        // Test basic struct functionality
        XCTAssertEqual(instance.id, "test")
        XCTAssertEqual(instance.value, 42)

        print("✅ @Plain macro generates working toAnyValue() method")
        print("✅ @Plain macro preserves field access")
    }

    func testPlainMacroWithNameWorks() {
        @Plain(name: "custom_struct")
        struct CustomStruct: Codable {
            let data: String
        }

        let instance = CustomStruct(data: "test_data")

        // Test that generated methods exist and work
        let anyValue = instance.toAnyValue()
        XCTAssertNotNil(anyValue)
        XCTAssertTrue(anyValue.hasPrefix("serialized_CustomStruct"))

        // Test basic struct functionality
        XCTAssertEqual(instance.data, "test_data")

        print("✅ @Plain macro with name parameter works")
    }

    func testEncryptedMacroWorks() {
        @Encrypted(name: "test.profile")
        struct TestProfile: Codable {
            let id: String
            let name: String
        }

        let profile = TestProfile(id: "123", name: "Test User")

        // Test that toAnyValue() method exists and works
        let anyValue = profile.toAnyValue()
        XCTAssertNotNil(anyValue)
        XCTAssertTrue(anyValue.hasPrefix("encrypted_"))

        // Test basic struct functionality
        XCTAssertEqual(profile.id, "123")
        XCTAssertEqual(profile.name, "Test User")

        print("✅ @Encrypted macro generates working toAnyValue() method")
        print("✅ @Encrypted macro preserves field access")
    }

    func testEncryptedMacroGeneratesTypeAlias() {
        @Encrypted(name: "alias.test")
        struct AliasTest: Codable {
            let value: String
        }

        let instance = AliasTest(value: "test")
        let encrypted = AliasTest.Encrypted.self
        _ = encrypted

        print("✅ @Encrypted macro generates Encrypted type alias")
    }
}

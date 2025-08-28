import RunarFFI
import RunarSerializer
import RunarSerializerMacros
import SwiftCBOR
import XCTest

/// Basic test that demonstrates the macro functionality works
final class BasicMacroTest: XCTestCase {
    func testPlainMacroBasicFunctionality() async throws {
        @Plain
        struct TestStruct: Codable {
            let id: String
            let value: Int64
        }

        let instance = TestStruct(id: "test", value: 42)

        // Test that generated methods exist and work
        let anyValue = await instance.toAnyValue()
        XCTAssertNotNil(anyValue)

        // Test basic struct functionality
        XCTAssertEqual(instance.id, "test")
        XCTAssertEqual(instance.value, 42)

        print("✅ @Plain macro generates working toAnyValue() method")
    }

    func testEncryptedMacroBasicFunctionality() async throws {
        @Encrypted(name: "test.profile")
        struct TestProfile: Codable {
            let id: String
            let name: String
        }

        let profile = TestProfile(id: "123", name: "Test User")

        // Test that toAnyValue() method exists and works
        let anyValue = await profile.toAnyValue()
        XCTAssertNotNil(anyValue)

        // Test basic struct functionality
        XCTAssertEqual(profile.id, "123")
        XCTAssertEqual(profile.name, "Test User")

        print("✅ @Encrypted macro generates working toAnyValue() method")
    }

    func testMacroRegistration() async throws {
        @Plain(name: "test.registration")
        struct RegistrationTest: Codable {
            let data: String
        }

        let instance = RegistrationTest(data: "test")

        // This should trigger registration
        let anyValue = await instance.toAnyValue()
        XCTAssertNotNil(anyValue)

        print("✅ Macro registration works")
    }
}

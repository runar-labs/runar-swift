import RunarSerializerMacros
import RunarSerializerMacrosPlaceholders
import XCTest

final class SimpleTest: XCTestCase {

    func testPlainMacroCompiles() {
        @Plain(name: "test_struct")
        struct TestStruct: Codable {
            let id: Int64
            let name: String
        }

        // Test that the struct compiles and has the expected structure
        let instance = TestStruct(id: 123, name: "test")
        _ = instance // Ensure it compiles

        // Test that the generated methods exist (they will fatalError for now)
        // This just tests that the macro generates the expected method signatures
        // let anyValue = instance.toAnyValue() // Would fatalError without dependencies
    }

    func testEncryptedMacroCompiles() {
        @Encrypted(name: "test_profile")
        struct TestProfile: Codable {
            let id: String
            @Runar("user") var username: String
            @Runar("system") var metadata: String
            let email: String  // Plain field
        }

        // Test that the struct compiles
        let profile = TestProfile(id: "123", username: "user", metadata: "data", email: "test@example.com")
        _ = profile // Ensure it compiles

        // Test that the Encrypted type alias exists
        let EncryptedType = TestProfile.Encrypted.self
        _ = EncryptedType // Ensure it compiles

        // The actual methods will fatalError without the real dependencies
        // This test just verifies the macro generates the expected structure
    }

    func testRunarMacroCompiles() {
        @Encrypted(name: "runar_test")
        struct RunarTest: Codable {
            let id: String
            @Runar("user") var userField: String
            @Runar("system") var systemField: String
            @Runar("user, system") var sharedField: String
        }

        // Test that the struct compiles with @Runar annotations
        let test = RunarTest(id: "test", userField: "user", systemField: "system", sharedField: "shared")
        _ = test // Ensure it compiles
    }
}

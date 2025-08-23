import RunarSerializerMacros

// Test basic macro functionality

@Plain(name: "simple_struct")
struct SimpleStruct: Codable {
    let id: Int64
    let name: String
}

@Encrypted(name: "test.profile")
struct TestProfile: Codable {
    let id: String
    @Runar("user") var privateData: String
    @Runar("system") var systemMetadata: String
    @Runar("user, system") var sharedData: String
}

@Encrypted(name: "empty.test")
struct EmptyTest: Codable {
    // No fields - just test basic functionality
}

// Test usage
func testMacros() {
    // Test Plain macro
    let simple = SimpleStruct(id: 123, name: "test")
    _ = simple // Ensure it compiles

    // Test Encrypted macro
    let profile = TestProfile(
        id: "123",
        privateData: "secret",
        systemMetadata: "system",
        sharedData: "shared"
    )
    _ = profile // Ensure it compiles

    let empty = EmptyTest()
    _ = empty // Ensure it compiles

    print("✅ All macros compile successfully!")
}

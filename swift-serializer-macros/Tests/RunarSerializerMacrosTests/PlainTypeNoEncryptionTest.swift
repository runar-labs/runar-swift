import RunarSerializer
import RunarSerializerMacros
import SwiftCBOR
import XCTest

/// Test for plain types without encryption - the "no encryption at all" use case
final class PlainTypeNoEncryptionTest: XCTestCase {
    
    func testPlainTypeSerializationWithoutKeystore() async throws {
        // Define a plain struct without any encryption
        @Plain(name: "plain_test.SimpleStruct")
        struct SimpleStruct: Codable {
            let id: String
            let value: Int64
            let isActive: Bool
        }
        
        // Create an instance
        let original = SimpleStruct(id: "test-123", value: 42, isActive: true)
        
        // Test serialization without keystore
        let anyValue = await original.toAnyValue()
        let serializedData = try await anyValue.serialize()
        
        // Test deserialization without keystore - this should work for plain types
        let deserializedValue = try AnyValue.deserialize(serializedData)
        let deserialized: SimpleStruct = try await deserializedValue.asType()
        
        // Verify the data matches
        XCTAssertEqual(deserialized.id, original.id)
        XCTAssertEqual(deserialized.value, original.value)
        XCTAssertEqual(deserialized.isActive, original.isActive)
        
        print("✅ Plain type serialization/deserialization without keystore works")
    }
    
    func testPlainTypeWithComplexFields() async throws {
        // Define a plain struct with more complex fields
        @Plain(name: "plain_test.ComplexStruct")
        struct ComplexStruct: Codable {
            let name: String
            let age: Int
            let scores: [Double]
            let metadata: [String: String]
        }
        
        // Create an instance
        let original = ComplexStruct(
            name: "John Doe",
            age: 30,
            scores: [85.5, 92.0, 78.5],
            metadata: ["department": "engineering", "level": "senior"]
        )
        
        // Test serialization without keystore
        let anyValue = await original.toAnyValue()
        let serializedData = try await anyValue.serialize()
        
        // Test deserialization without keystore
        let deserializedValue = try AnyValue.deserialize(serializedData)
        let deserialized: ComplexStruct = try await deserializedValue.asType()
        
        // Verify the data matches
        XCTAssertEqual(deserialized.name, original.name)
        XCTAssertEqual(deserialized.age, original.age)
        XCTAssertEqual(deserialized.scores, original.scores)
        XCTAssertEqual(deserialized.metadata, original.metadata)
        
        print("✅ Complex plain type serialization/deserialization without keystore works")
    }
    
    func testPlainTypeInContainer() async throws {
        // Define a plain struct
        @Plain(name: "plain_test.ContainerStruct")
        struct ContainerStruct: Codable {
            let items: [String]
            let count: Int
        }
        
        // Create an instance
        let original = ContainerStruct(items: ["item1", "item2", "item3"], count: 3)
        
        // Test serialization without keystore
        let anyValue = await original.toAnyValue()
        let serializedData = try await anyValue.serialize()
        
        // Test deserialization without keystore
        let deserializedValue = try AnyValue.deserialize(serializedData)
        let deserialized: ContainerStruct = try await deserializedValue.asType()
        
        // Verify the data matches
        XCTAssertEqual(deserialized.items, original.items)
        XCTAssertEqual(deserialized.count, original.count)
        
        print("✅ Plain type with containers serialization/deserialization without keystore works")
    }
    
    func testPlainTypeWithNestedStructs() async throws {
        // Define nested plain structs
        @Plain(name: "plain_test.NestedStruct")
        struct NestedStruct: Codable {
            let user: UserInfo
            let settings: AppSettings
        }
        
        @Plain(name: "plain_test.UserInfo")
        struct UserInfo: Codable {
            let id: String
            let name: String
        }
        
        @Plain(name: "plain_test.AppSettings")
        struct AppSettings: Codable {
            let theme: String
            let notifications: Bool
        }
        
        // Create an instance
        let original = NestedStruct(
            user: UserInfo(id: "user-123", name: "Alice"),
            settings: AppSettings(theme: "dark", notifications: true)
        )
        
        // Test serialization without keystore
        let anyValue = await original.toAnyValue()
        let serializedData = try await anyValue.serialize()
        
        // Test deserialization without keystore
        let deserializedValue = try AnyValue.deserialize(serializedData)
        let deserialized: NestedStruct = try await deserializedValue.asType()
        
        // Verify the data matches
        XCTAssertEqual(deserialized.user.id, original.user.id)
        XCTAssertEqual(deserialized.user.name, original.user.name)
        XCTAssertEqual(deserialized.settings.theme, original.settings.theme)
        XCTAssertEqual(deserialized.settings.notifications, original.settings.notifications)
        
        print("✅ Nested plain types serialization/deserialization without keystore works")
    }
}

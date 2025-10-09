import RunarSerializerMacros

// Simple example showing macro-generated code structure

@Plain(name: "simple_example")
struct SimpleExample: Codable {
    let id: Int64
    let name: String
}

@Encrypted(name: "user_profile")
struct UserProfile: Codable {
    let id: String
    @Runar("user") var username: String
    @Runar("system") var metadata: String
    let email: String // Plain field (no @Runar)
}

// This will generate code like:
//
// extension SimpleExample {
//     func toAnyValue() -> Any { ... }
//     static func fromAnyValue(_ anyValue: Any) async throws -> SimpleExample { ... }
// }
//
// extension UserProfile {
//     typealias Encrypted = EncryptedUserProfile
//
//     func toAnyValue() -> Any { ... }
//     func encryptWithKeystore(_ keystore: Any, _ resolver: Any) throws -> EncryptedUserProfile { ... }
//
//     struct EncryptedUserProfile: Codable {
//         let id: String                    // Plain field
//         let email: String                 // Plain field
//         let username_encrypted: Data?     // @Runar("user") field
//         let metadata_encrypted: Data?     // @Runar("system") field
//
//         func decryptWithKeystore(_ keystore: Any) throws -> UserProfile { ... }
//     }
// }

func example() {
    let simple = SimpleExample(id: 123, name: "test")
    _ = simple // Struct with generated serialization methods

    let profile = UserProfile(id: "123", username: "user", metadata: "data", email: "test@example.com")
    _ = profile // Struct with generated encryption methods

    print("✅ Macros generate proper struct definitions and methods")
}

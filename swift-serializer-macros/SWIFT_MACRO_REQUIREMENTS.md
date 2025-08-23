# 🎯 Swift Serializer Macro Requirements

## 📋 **Requirements Based on Rust `encryption_test.rs` Analysis**

### **MANDATORY: Follow Code Standards**
- ❌ **NO MOCKS, NO SHORTCUTS, NO HACKS**
- ❌ **NO SIMPLIFIED IMPLEMENTATIONS**
- ❌ **NO PLACEHOLDER FUNCTIONS**
- ❌ **NO HARDCODED TEST VALUES**
- ✅ **PRODUCTION-READY CODE ONLY**
- ✅ **REAL IMPLEMENTATIONS ONLY**
- ✅ **COMPLETE FEATURES ONLY**

---

## ✅ **EXISTING INFRASTRUCTURE (Already Complete)**

### **1. AnyValue enum - Real serialization format**
**✅ FULLY IMPLEMENTED** in `swift-serializer/Sources/RunarSerializer/AnyValue.swift`:
- Complete binary serialization format with 5-byte header
- Lazy deserialization support
- CBOR encoding/decoding for all types
- Encrypted data handling
- Full primitive type support (i8, i16, i32, i64, u8, u16, u32, u64, f32, f64, bool, string, bytes)
- Container support (list, map, struct)
- JSON support
- **Lines 1-1128** - Comprehensive implementation

### **2. EnvelopeCrypto protocol - Real encryption/decryption**
**✅ FULLY IMPLEMENTED** in `swift-ffi/Sources/RunarFFI/FFIKeyStore.swift`:
- Real FFI-backed encryption/decryption
- `FFIKeyStore` class implementing the protocol
- Network and profile-based encryption
- CBOR serialization of envelope data
- **Lines 19-199** - Complete FFI integration

### **3. TypeNameRegistry - Real type registration system**
**✅ FULLY IMPLEMENTED** in `swift-serializer/Sources/RunarSerializer/TypeNameRegistry.swift`:
- Actor-based concurrent registry
- Bidirectional Swift ↔ Wire name mappings
- JSON converter registration
- Decoder registration
- Built-in primitive type registration
- **Lines 3-89** - Complete implementation

### **4. LabelResolver protocol**
**✅ FULLY IMPLEMENTED** in `swift-serializer/Sources/RunarSerializer/EncryptionTypes.swift`:
- Protocol for resolving labels to key information
- `LabelKeyInfo` struct for key mapping data
- **Lines 17-20** - Complete protocol definition

### **5. KeyStore typealias**
**✅ DEFINED** in `swift-serializer/Sources/RunarSerializer/SerializationContext.swift`:
```swift
public typealias KeyStore = RunarFFI.EnvelopeCrypto
```

---

## 🚧 **WHAT NEEDS TO BE IMPLEMENTED (The Macros)**

The **ONLY** missing pieces are the actual Swift macro implementations that use these existing components:

---

## 🔧 **@Encrypted Macro Requirements**

### **1. Generated Methods on Original Struct**
For any struct annotated with `@Encrypted(name: "...")`, the macro **MUST** generate:

```swift
extension TestProfile {
    /// Encrypt this struct instance using provided keystore and resolver
    /// Returns: New encrypted version of this struct
    func encryptWithKeystore(
        _ keystore: any EnvelopeCrypto,
        _ resolver: any LabelResolver
    ) throws -> EncryptedTestProfile

    /// Convert to AnyValue for serialization (entry point for ArcValue integration)
    func toAnyValue() -> AnyValue
}
```

### **2. Generated Encrypted Type**
The macro **MUST** generate a new type called `EncryptedTestProfile` with:

#### **2.1 Plain Fields (Always Present)**
```swift
struct EncryptedTestProfile {
    /// Plain fields that are never encrypted
    let id: String  // Same as original field
    // ... other non-encrypted fields
}
```

#### **2.2 Encrypted Fields (Based on @Runar Labels)**
```swift
struct EncryptedTestProfile {
    let id: String  // Plain field

    /// Encrypted fields based on @Runar labels:
    let user_encrypted: Data?        // @Runar("user") field
    let system_encrypted: Data?      // @Runar("system") field
    let search_encrypted: Data?      // @Runar("search") field
    let system_only_encrypted: Data? // @Runar("system_only") field
    let multi_label_encrypted: Data? // @Runar("user, system") field

    /// Fields without @Runar labels are NOT encrypted
    let plainField: String  // No encryption
}
```

#### **2.3 Generated Methods on Encrypted Type**
```swift
extension EncryptedTestProfile {
    /// Decrypt this encrypted instance back to original type
    func decryptWithKeystore(
        _ keystore: any EnvelopeCrypto
    ) throws -> TestProfile
}
```

---

## 🔧 **@Plain Macro Requirements**

### **1. Generated Methods on Original Struct**
For any struct annotated with `@Plain(name: "...")`, the macro **MUST** generate:

```swift
extension SimpleStruct {
    /// Convert to AnyValue for serialization (entry point for ArcValue integration)
    func toAnyValue() -> AnyValue

    /// Convert from AnyValue back to struct
    static func fromAnyValue(_ anyValue: AnyValue) throws -> SimpleStruct
}
```

### **2. NO Encrypted Type Generation**
- `@Plain` **DOES NOT** generate encrypted versions
- Only generates serialization methods

---

## 🔧 **@Runar Macro Requirements**

### **1. Field-Level Label Annotation**
```swift
@Encrypted(name: "test.profile")
struct TestProfile: Codable {
    let id: String                    // No label = plain field
    @Runar("user") var name: String   // Label = encrypted field
    @Runar("system") var data: String // Label = encrypted field
    @Runar("user, system") var shared: String // Multiple labels
}
```

### **2. Validation Rules**
- **MUST** be applied to variable declarations only
- **MUST** have at least one label
- **CANNOT** be applied to struct declarations
- **MUST** validate label syntax

### **3. Integration with @Encrypted**
The `@Encrypted` macro **MUST** read `@Runar` labels to determine:
- Which fields to encrypt
- What encryption labels to use
- How to generate encrypted field names

---

## 🔧 **Wire Name Integration**

### **1. Registry Registration**
Both `@Encrypted` and `@Plain` macros **MUST**:

```swift
// Generated bootstrap code
private static let _runarBootstrap: Void = {
    await TypeNameRegistry.shared.registerTypeName(
        TestProfile.self,
        wireName: "test.profile"  // From name parameter
    )
    await TypeNameRegistry.shared.registerDecoder(
        for: "test.profile",
        decoder: { data in
            let decoder = SwiftCBOR.CodableCBORDecoder()
            return try decoder.decode(TestProfile.self, from: data)
        }
    )
}()
```

### **2. Custom Wire Names**
- `@Encrypted(name: "custom.wire.Name")` → Wire name: `"custom.wire.Name"`
- `@Plain(name: "simple_struct")` → Wire name: `"simple_struct"`
- Default: struct name if no `name` parameter provided

---

## 🧪 **Test Requirements (MUST Match Rust `encryption_test.rs`)**

### **1. Basic Encryption Test**
```swift
func testEncryptionBasic() throws {
    let context = buildTestContext() // Real keystore setup

    let original = TestProfile(
        id: "123",
        name: "Test User",           // @Runar("system")
        private: "secret123",        // @Runar("user")
        email: "test@example.com",   // @Runar("search")
        systemMetadata: "system_data" // @Runar("system_only")
    )

    // Test encryption - MUST return EncryptedTestProfile
    let encrypted: EncryptedTestProfile =
        try original.encryptWithKeystore(context.mobileKeystore, context.resolver)

    // Test encrypted fields exist and are populated
    XCTAssertEqual(encrypted.id, "123")
    XCTAssertNotNil(encrypted.system_encrypted)    // @Runar("system") field
    XCTAssertNotNil(encrypted.user_encrypted)      // @Runar("user") field
    XCTAssertNotNil(encrypted.search_encrypted)    // @Runar("search") field
    XCTAssertNotNil(encrypted.system_only_encrypted) // @Runar("system_only") field

    // Test decryption with mobile keystore
    let decryptedMobile = try encrypted.decryptWithKeystore(context.mobileKeystore)
    XCTAssertEqual(decryptedMobile.id, original.id)
    XCTAssertEqual(decryptedMobile.name, original.name)         // Has access
    XCTAssertEqual(decryptedMobile.private, original.private)   // Has access
    XCTAssertEqual(decryptedMobile.email, original.email)       // Has access
    XCTAssertEqual(decryptedMobile.systemMetadata, "")          // NO access

    // Test decryption with node keystore
    let decryptedNode = try encrypted.decryptWithKeystore(context.nodeKeystore)
    XCTAssertEqual(decryptedNode.id, original.id)
    XCTAssertEqual(decryptedNode.name, original.name)           // Has access
    XCTAssertEqual(decryptedNode.private, "")                   // NO access
    XCTAssertEqual(decryptedNode.email, original.email)         // Has access
    XCTAssertEqual(decryptedNode.systemMetadata, original.systemMetadata) // Has access
}
```

### **2. ArcValue Integration Test**
```swift
func testEncryptionInArcValue() throws {
    let context = buildTestContext()
    let profile = TestProfile(...) // With @Runar labels

    // Test AnyValue serialization
    let anyValue = profile.toAnyValue()
    // anyValue should be proper AnyValue enum, not String

    // Test ArcValue integration (when AnyValue is implemented)
    // let arcValue = ArcValue.new_struct(profile)
    // let serialized = arcValue.serialize(context)
}
```

### **3. Field Label Variations**
```swift
@Encrypted(name: "label.test")
struct LabelTest: Codable {
    let plain: String                    // No label = plain
    @Runar("user") var userOnly: String  // Single label
    @Runar("system") var systemOnly: String // Single label
    @Runar("user, system") var both: String // Multiple labels
    @Runar("search") var search: String   // Single label
}
```

---

## 🔗 **Dependencies (All Already Implemented)**

### **✅ 1. EnvelopeCrypto Protocol**
**EXISTS** in `swift-ffi/Sources/RunarFFI/FFIKeyStore.swift:19-23`:
- ✅ Real FFI-backed encryption/decryption
- ✅ Network and profile-based encryption
- ✅ `FFIKeyStore` concrete implementation

### **✅ 2. LabelResolver Protocol**
**EXISTS** in `swift-serializer/Sources/RunarSerializer/EncryptionTypes.swift:17-20`:
- ✅ Protocol for resolving labels to key information
- ✅ `LabelKeyInfo` struct for key mapping data

### **✅ 3. AnyValue Type**
**EXISTS** in `swift-serializer/Sources/RunarSerializer/AnyValue.swift:1-1128`:
- ✅ Complete binary serialization format with 5-byte header
- ✅ Lazy deserialization support
- ✅ Full primitive and container type support
- ✅ CBOR encoding/decoding
- ✅ Encrypted data handling

### **✅ 4. TypeNameRegistry**
**EXISTS** in `swift-serializer/Sources/RunarSerializer/TypeNameRegistry.swift:3-89`:
- ✅ Actor-based concurrent registry
- ✅ Bidirectional Swift ↔ Wire name mappings
- ✅ JSON converter registration
- ✅ Decoder registration
- ✅ Built-in primitive type registration

### **✅ 5. KeyStore TypeAlias**
**EXISTS** in `swift-serializer/Sources/RunarSerializer/SerializationContext.swift:8`:
```swift
public typealias KeyStore = RunarFFI.EnvelopeCrypto
```

---

## 🚫 **PROHIBITED (Code Standards Violations)**

### **❌ NEVER Implement These**
- `return "encrypted_\(self)"` (String hacks)
- `return "serialized_simple_struct"` (hardcoded strings)
- Placeholder methods that don't actually encrypt/decrypt
- Mock implementations
- Simplified versions
- Any code that doesn't match Rust functionality exactly

### **✅ MUST Implement These**
- Real encryption/decryption using EnvelopeCrypto
- Proper AnyValue generation (not strings)
- Full field-level access control based on labels
- Complete TypeNameRegistry integration
- Production-ready error handling

---

## 🔄 **Implementation Workflow**

### **✅ Phase 1: Dependencies - COMPLETE**
- ✅ `EnvelopeCrypto` protocol - EXISTS in `swift-ffi`
- ✅ `LabelResolver` protocol - EXISTS in `swift-serializer`
- ✅ `AnyValue` enum - EXISTS in `swift-serializer`
- ✅ `TypeNameRegistry` actor - EXISTS in `swift-serializer`
- ✅ `KeyStore` typealias - EXISTS in `swift-serializer`

### **🚧 Phase 2: @Runar Macro - NEEDS IMPLEMENTATION**
1. Implement field-level label validation using existing `LabelResolver`
2. Generate label metadata for `@Encrypted` macro to consume
3. **Use existing components, no new dependencies**

### **🚧 Phase 3: @Encrypted Macro - NEEDS IMPLEMENTATION**
1. Generate `encryptWithKeystore()` method using existing `EnvelopeCrypto`
2. Generate `EncryptedTestProfile` type with proper encrypted fields based on `@Runar` labels
3. Generate `decryptWithKeystore()` method on encrypted type using existing `EnvelopeCrypto`
4. Generate `toAnyValue()` method using existing `AnyValue`
5. Integrate with existing `TypeNameRegistry`

### **🚧 Phase 4: @Plain Macro - NEEDS IMPLEMENTATION**
1. Generate `toAnyValue()` method using existing `AnyValue`
2. Generate `fromAnyValue()` method using existing `AnyValue`
3. Integrate with existing `TypeNameRegistry`

### **🚧 Phase 5: Real Tests - NEEDS IMPLEMENTATION**
1. Create tests that use real `FFIKeyStore` (no mocks)
2. Test actual encryption/decryption workflows
3. Test field-level access control
4. Test `AnyValue` serialization integration
5. **MUST match Rust `encryption_test.rs` functionality exactly**

---

## 🎯 **Final Goal**

The Swift macro system **MUST** provide the **exact same functionality** as Rust's `encryption_test.rs`:

### **✅ Infrastructure - COMPLETE**
- ✅ Real `EnvelopeCrypto` protocol (FFI-backed)
- ✅ Real `LabelResolver` protocol
- ✅ Real `AnyValue` enum with full serialization
- ✅ Real `TypeNameRegistry` actor
- ✅ Real `FFIKeyStore` implementation
- ✅ Production-ready encryption/decryption

### **🚧 Macros - NEEDS IMPLEMENTATION**
- 🚧 `@Runar` macro for field-level labels
- 🚧 `@Encrypted` macro using existing `EnvelopeCrypto` + `AnyValue`
- 🚧 `@Plain` macro using existing `AnyValue`
- 🚧 Real integration tests using existing components

### **🚫 ABSOLUTELY PROHIBITED**
- ❌ String hacks like `return "encrypted_\(self)"`
- ❌ Placeholder methods that don't actually work
- ❌ Mock implementations
- ❌ Simplified versions
- ❌ Any code that doesn't use the existing real components

**NO EXCEPTIONS. NO SIMPLIFICATIONS. NO HACKS. USE THE EXISTING INFRASTRUCTURE.**

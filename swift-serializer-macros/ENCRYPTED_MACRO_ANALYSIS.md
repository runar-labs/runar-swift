# @Encrypted Macro Analysis & Lessons Learned

## 📋 Overview
This document analyzes the `@Encrypted` macro implementation, documenting all issues faced, current problems, and the path forward to achieve working field-level encryption.

## 🎯 Goal & Desired End State

### **What @Encrypted Should Do (Based on Rust Implementation)**
```swift
@Encrypted(name: "encryption_test.TestProfile")
struct TestProfile: Codable {
    let id: String
    @Runar("system") var name: String
    @Runar("user") var privateData: String
    @Runar("search") var email: String
    @Runar("system_only") var systemMetadata: String
}

// Should generate:
// 1. EncryptedTestProfile struct with encrypted field groups
// 2. encryptWithKeystore() method for field-level encryption
// 3. decryptWithKeystore() method for field-level decryption
// 4. Automatic type registration in TypeNameRegistry
// 5. Integration with AnyValue serialization system
```

### **Expected Behavior (Mirroring Rust encryption_test.rs)**
- **Field Grouping**: Fields with same @Runar label are grouped together for encryption
- **Label-Based Access**: "user" fields accessible by user keystores, "system" by system keystores
- **Encryption**: `profile.encryptWithKeystore(keystore, resolver)` → `EncryptedTestProfile`
- **Decryption**: `encrypted.decryptWithKeystore(keystore)` → `TestProfile`
- **Access Control**: Decryption returns empty/default values for inaccessible fields
- **Wire Name**: Automatic registration with TypeNameRegistry using #[runar(name = "...")]
- **Registry Integration**: Automatic registration of encryptor/decryptor functions
- **JSON Conversion**: Automatic registration of JSON converters
- **AnyValue Integration**: Seamless integration with AnyValue serialization system

### **Rust Implementation Architecture**

#### **1. Macro System (lib.rs)**
- **`Plain` derive**: Simple trait implementations, identity encryption
- **`Encrypt` derive**: Complex field grouping, sub-struct generation, registry registration
- **`runar` attribute**: Field-level label annotation system
- **`#[ctor]` integration**: Automatic type registration at program startup

#### **2. Trait System (traits.rs)**
- **`RunarEncryptable`**: Marker trait for encryption capability
- **`RunarEncrypt<T>`**: Encryption with associated encrypted type
- **`RunarDecrypt<T>`**: Decryption with associated plain type
- **`LabelResolver`**: Dynamic label-to-key mapping
- **`SerializationContext`**: Consolidated encryption parameters

#### **3. Encryption System (encryption.rs)**
- **`EncryptedLabelGroup`**: Container for label-grouped encrypted data
- **`encrypt_label_group()`**: Field-group encryption using envelope encryption
- **`decrypt_label_group()`**: Field-group decryption with access control
- **Envelope Integration**: Uses `runar_keys::EnvelopeCrypto` for actual encryption

#### **4. Registry System (registry.rs)**
- **Global registries**: Encryptors, decryptors, JSON converters, wire names
- **Type registration**: Automatic registration using `#[ctor]`
- **Wire name mapping**: Platform-neutral type names
- **Dynamic lookup**: Runtime type resolution for serialization

#### **5. ArcValue System (arc_value.rs)**
- **Lazy serialization**: Creates serialization functions with encryption context
- **Context-aware encryption**: Encryption parameters passed to serialization
- **Registry integration**: Uses registered encryptor/decryptor functions
- **Multi-keystore support**: Different keystores for different access levels

## 🔧 Issues Faced & Current Problems

### **1. Missing Core Architecture Components**

#### **No Field Grouping System**
**Current**: Individual field processing
**Rust**: Groups fields by @Runar labels, creates sub-structs per label group
```rust
// Rust generates sub-structs like:
struct SystemFields { name: String }
struct UserFields { privateData: String, email: String }
struct SystemOnlyFields { systemMetadata: String }
```

#### **No Label Resolution System**
**Current**: No label-to-key mapping
**Rust**: `LabelResolver` trait with `ConfigurableLabelResolver` implementation
- Maps labels to public keys and network IDs
- Supports "user", "system", "search", "system_only" labels
- Dynamic label resolution at runtime

#### **No Registry System**
**Current**: No type registration
**Rust**: Global registries with automatic registration using `#[ctor]`
- Encryptor registry: `TypeId -> EncryptFn`
- Decryptor registry: `TypeId -> DecryptFn`
- JSON converter registry: `TypeId -> ToJsonFn`
- Wire name registry: `rust_name -> wire_name`

#### **No Sub-Struct Generation**
**Current**: Simple encrypted field generation
**Rust**: Generates separate structs for each label group
- `SystemFields`, `UserFields`, `SearchFields`, `SystemOnlyFields`
- Each sub-struct contains fields with the same label
- Proper serialization/deserialization per label group

### **2. Compilation Errors in Macro Expansion**

#### **Field Ordering Issues**
```swift
// ERROR: incorrect argument labels in call
return EncryptedTestProfile(
    id: self.id,
    name_encrypted: encryptedFields["name"] ?? Data(),  // Wrong order
    email_encrypted: encryptedFields["email"] ?? Data(),
    systemMetadata_encrypted: encryptedFields["systemMetadata"] ?? Data(),
    privateData_encrypted: encryptedFields["privateData"] ?? Data()
)
```

**Root Cause**: Field processing doesn't preserve struct field declaration order.

#### **Missing Type Casting Logic**
```swift
// ERROR: cannot convert value of type 'String?' to expected argument type 'AnyHashable'
let fieldValue = Mirror(reflecting: self).children
    .first(where: { $0.label == fieldName })?.value as Any
```

**Root Cause**: `Mirror` returns `Any?` but code assumes specific types.

#### **Variable Scope Issues**
```swift
// ERROR: cannot find 'fieldLabels' in scope
for (fieldName, labels) in \(raw: fieldLabels) {  // fieldLabels not in scope
```

**Root Cause**: `fieldLabels` parameter not accessible in macro expansion context.

### **2. Runtime Logic Issues**

#### **Field Encryption Logic Problems**
```swift
// Current implementation has issues with:
for label in (labels as? [String]) ?? [] {  // Unnecessary casting
    if let labelInfo = resolver.resolveLabel(label) {
        // Encryption logic
    }
}
```

**Problems**:
- Unnecessary type casting of `[String]` to `[String]`
- No proper error handling for failed encryption
- Missing support for multiple labels per field

#### **Decryption Logic Simplifications**
```swift
// Current implementation is too simplified:
var decryptedFields: [String: Any] = [:]
// No actual decryption, just placeholder logic
```

**Missing**:
- Real field decryption using keystore
- Proper error handling
- Access control based on keystore permissions

### **3. Design & Architecture Issues**

#### **Over-Complex Field Processing**
The current implementation tries to:
1. Use reflection to iterate over all struct fields
2. Find @Runar annotations
3. Process labels for each field
4. Encrypt each field individually
5. Generate proper constructor calls

**Problem**: This is overly complex and error-prone.

#### **Missing Integration Points**
- No proper integration with `SerializationContext`
- No proper wire name registration
- No integration with `TypeNameRegistry`
- Missing access control logic

### **4. Test Environment Issues**

#### **Disabled Test Files**
The following test files are disabled due to compilation errors:
- `WorkingTest.swift.disabled`
- `SimpleWorkingTest.swift.disabled`
- `SimpleTest.swift.disabled`

#### **Missing Test Coverage**
- No tests for actual encryption/decryption
- No tests for access control scenarios
- No tests for different keystore types
- No tests for field-level label processing

## 🛠️ Current Implementation Status

### **What's Working**
✅ **@Plain Macro**: Fully functional with `toAnyValue()` generation
✅ **Basic Structure**: Macro expansion framework is in place
✅ **Code Generation**: Basic code generation works
✅ **Type System**: Integration with `RunarSerializer` and `RunarFFI`

### **What's Broken**
❌ **@Encrypted Macro**: Compilation errors prevent usage
❌ **Field-Level Encryption**: Logic exists but has bugs
❌ **@Runar Integration**: Field annotation processing broken
❌ **Constructor Generation**: Field ordering issues
❌ **Reflection Logic**: Type casting and scope issues

## 🎨 Lessons Learned

### **1. Architecture-First Approach Required**
- **Lesson**: Can't implement macros without understanding the full system architecture
- **Solution**: Analyze the complete Rust implementation before starting Swift implementation
- **Implementation**: Map every component: traits, registries, encryption system, ArcValue integration

### **2. Registry System is Core**
- **Lesson**: Rust's registry system is essential for dynamic type resolution
- **Solution**: Implement equivalent registry system in Swift
- **Implementation**: TypeNameRegistry, encryptor/decryptor registries, JSON converters

### **3. Field Grouping is Essential**
- **Lesson**: Individual field encryption is inefficient and complex
- **Solution**: Group fields by @Runar labels, encrypt as groups
- **Implementation**: Generate sub-structs per label group (SystemFields, UserFields, etc.)

### **4. Label Resolution Must Be Dynamic**
- **Lesson**: Hard-coded label mapping won't work for production
- **Solution**: Implement `LabelResolver` trait with runtime configuration
- **Implementation**: Support multiple keystores, network IDs, profile key mappings

### **5. Compilation vs Runtime Complexity**
- **Lesson**: Moving complexity from runtime to compile-time reduces errors
- **Solution**: Generate more code at compile-time, less reflection at runtime
- **Implementation**: Generate sub-structs, trait implementations, registry registrations

### **6. Integration Points Critical**
- **Lesson**: AnyValue serialization integration requires careful design
- **Solution**: Ensure macro-generated types work seamlessly with existing serialization
- **Implementation**: Proper toAnyValue() integration, SerializationContext support

### **7. Test-Driven Development Essential**
- **Lesson**: Complex macros require comprehensive testing at every step
- **Solution**: Test compilation, basic functionality, integration, edge cases
- **Implementation**: Create test suite that mirrors Rust's encryption_test.rs

## 🏗️ Architecture Problems & Missing Components

### **1. Complete Architecture Missing**
**Current**: Fragmented components without integration
**Missing**: Complete system architecture matching Rust implementation
**Required Components**:
- `RunarEncryptable` protocol (marker trait)
- `RunarEncrypt` protocol with associated encrypted type
- `RunarDecrypt` protocol with associated plain type
- `LabelResolver` protocol for dynamic label mapping
- `SerializationContext` for consolidated parameters
- Registry system for type registration
- `EncryptedLabelGroup` for label-grouped encryption

### **2. No Registry System**
**Current**: No type registration or lookup
**Missing**: Global registries equivalent to Rust's system
**Required Registries**:
- Encryptor registry: `Type -> EncryptFn`
- Decryptor registry: `Type -> DecryptFn`
- JSON converter registry: `Type -> ToJsonFn`
- Wire name registry: `rust_name -> wire_name`
- Automatic registration using equivalent of `#[ctor]`

### **3. No Field Grouping System**
**Current**: Individual field processing
**Missing**: Label-based field grouping system
**Required**:
- Parse @Runar annotations on fields
- Group fields by label ("user", "system", "search", "system_only")
- Generate sub-structs for each label group
- Proper label ordering (system = 0, user = 1, others = 2)

### **4. No Label Resolution System**
**Current**: No label-to-key mapping
**Missing**: Dynamic label resolution infrastructure
**Required**:
- `LabelResolver` protocol for label-to-key mapping
- `ConfigurableLabelResolver` implementation
- Support for profile public keys and network IDs
- Runtime label configuration

### **5. No Sub-Struct Generation**
**Current**: Simple encrypted field generation
**Missing**: Proper sub-struct generation per label group
**Example**:
```swift
// Should generate:
struct SystemFields {
    let name: String
}
struct UserFields {
    let privateData: String
    let email: String
}
struct SystemOnlyFields {
    let systemMetadata: String
}
```

### **6. No Registry Integration**
**Current**: No automatic type registration
**Missing**: Integration with TypeNameRegistry and other registries
**Required**:
- Automatic wire name registration
- Automatic encryptor/decryptor registration
- Automatic JSON converter registration
- Program startup registration (equivalent to Rust's `#[ctor]`)

### **7. No AnyValue Integration**
**Current**: Simple `AnyValue.struct(self)` wrapper
**Missing**: Full ArcValue-equivalent integration
**Required**:
- Context-aware serialization
- Encryption parameter passing
- Registry-based type resolution
- Multi-keystore support

### **8. No Access Control System**
**Current**: No access control logic
**Missing**: Keystore-based field access control
**Required**:
- Decryption returns empty values for inaccessible fields
- Different keystores have different access levels
- Proper error handling for access denied scenarios

## 🎯 Desired Implementation Approach

### **Simplified Architecture**
```swift
// Instead of complex reflection:
@Encrypted(name: "test.Profile")
struct Profile: Codable {
    @Runar("user") var data: String
}

// Generate:
// - Profile.Encrypted type
// - encryptWithKeystore() method
// - decryptWithKeystore() method
```

### **Clean Code Generation**
- No reflection in macro expansion
- Proper field ordering in constructors
- Clean, syntax-error-free generated code
- Proper integration with existing infrastructure

### **Working Test Suite**
```swift
func testEncryptionBasic() throws {
    let original = TestProfile(id: "123", name: "Test", data: "secret")
    let encrypted = try original.encryptWithKeystore(keystore, resolver)
    let decrypted = try encrypted.decryptWithKeystore(keystore)
    XCTAssertEqual(decrypted, original)
}
```

## 📋 Comprehensive Implementation Roadmap

### **Phase 1: Core Architecture (Foundation)**
1. **Implement Core Protocols**:
   - `RunarEncryptable` protocol (marker trait)
   - `RunarEncrypt` protocol with associated encrypted type
   - `RunarDecrypt` protocol with associated plain type
   - `LabelResolver` protocol for dynamic label mapping
   - `SerializationContext` for consolidated parameters

2. **Create Registry System**:
   - `TypeNameRegistry` for wire name mapping
   - Encryptor/decryptor registries
   - JSON converter registry
   - Automatic registration system

3. **Implement Label Resolution System**:
   - `LabelResolver` protocol implementation
   - `ConfigurableLabelResolver` for runtime configuration
   - Support for profile keys and network IDs

### **Phase 2: Macro System Enhancement**
4. **Fix Compilation Errors**:
   - Resolve field ordering issues in constructor generation
   - Fix reflection type casting problems
   - Resolve variable scope issues
   - Remove syntax errors in generated code

5. **Implement Field Grouping System**:
   - Parse @Runar field annotations
   - Group fields by labels ("user", "system", "search", "system_only")
   - Generate sub-structs per label group
   - Implement proper label ordering

6. **Generate Proper Encrypted Types**:
   - Create `EncryptedLabelGroup` equivalent
   - Generate sub-structs for each label group
   - Implement label-based encryption/decryption functions

### **Phase 3: Integration & Testing**
7. **Registry Integration**:
   - Automatic type registration at startup
   - Wire name registration from `@Encrypted(name = "...")`
   - Encryptor/decryptor function registration

8. **AnyValue Integration**:
   - Replace simple `toAnyValue()` with context-aware serialization
   - Support `SerializationContext` parameter
   - Registry-based type resolution

9. **Access Control System**:
   - Implement keystore-based field access control
   - Return empty values for inaccessible fields
   - Multi-keystore support

### **Phase 4: Testing & Validation**
10. **Comprehensive Test Suite**:
    - Create tests equivalent to Rust's `encryption_test.rs`
    - Test all access control scenarios
    - Test different keystore configurations
    - Test label resolution edge cases

11. **Integration Testing**:
    - Test with real keystores from `swift-ffi`
    - Test AnyValue serialization integration
    - Test cross-platform compatibility

### **Phase 5: Production Readiness**
12. **Performance Optimization**:
    - Optimize encryption/decryption performance
    - Minimize reflection usage
    - Cache frequently used operations

13. **Documentation & Examples**:
    - Comprehensive documentation
    - Working examples for all scenarios
    - Migration guides from simple to encrypted usage

14. **Error Handling & Edge Cases**:
    - Comprehensive error handling
    - Graceful handling of missing keystores
    - Proper fallbacks for decryption failures

## 🔄 Next Steps & Implementation Strategy

### **Phase 1: Foundation (Immediate - 1 week)**
1. **Complete Architecture Analysis**: ✅ DONE - This document
2. **Implement Core Protocols**: `RunarEncryptable`, `RunarEncrypt`, `RunarDecrypt`, `LabelResolver`
3. **Create Basic Registry System**: `TypeNameRegistry` with wire name mapping
4. **Implement LabelResolver**: Basic label-to-key mapping support

### **Phase 2: Macro Fixes (Week 2)**
5. **Fix Compilation Errors**: Resolve all syntax and type errors in macro expansion
6. **Implement Field Grouping**: Parse @Runar annotations, group fields by label
7. **Fix Constructor Generation**: Ensure proper field ordering in generated constructors
8. **Generate Sub-Structs**: Create label-grouped sub-structs (SystemFields, UserFields, etc.)

### **Phase 3: Encryption Logic (Week 3)**
9. **Implement encrypt_label_group()**: Field-group encryption using envelope encryption
10. **Implement decrypt_label_group()**: Field-group decryption with access control
11. **Create EncryptedLabelGroup**: Container for encrypted field groups
12. **Integrate with EnvelopeCrypto**: Use existing FFI keystore infrastructure

### **Phase 4: Integration (Week 4)**
13. **Registry Integration**: Automatic type registration at startup
14. **AnyValue Enhancement**: Context-aware serialization with keystore support
15. **Access Control**: Implement keystore-based field access control
16. **Multi-Keystore Support**: Support different keystores for different access levels

### **Phase 5: Testing & Validation (Week 5)**
17. **Create Comprehensive Tests**: Mirror Rust's `encryption_test.rs` exactly
18. **Integration Testing**: Test with real keystores from `swift-ffi`
19. **Cross-Platform Testing**: Ensure compatibility with Rust serialization
20. **Performance Testing**: Optimize and benchmark encryption operations

### **Success Criteria**
- ✅ **Compiles without errors** for all @Encrypted usage patterns
- ✅ **Passes all access control tests** matching Rust behavior
- ✅ **Integrates seamlessly** with existing keystore infrastructure
- ✅ **Maintains performance** equivalent to Rust implementation
- ✅ **Supports all label types** ("user", "system", "search", "system_only")
- ✅ **Handles edge cases** gracefully (missing keystores, invalid labels, etc.)

### **Risk Mitigation**
- **Incremental Development**: Implement and test one component at a time
- **Frequent Testing**: Test compilation and basic functionality after each change
- **Reference Implementation**: Use Rust code as the authoritative specification
- **Simple First**: Start with single-label encryption, then expand to multi-label
- **Fallback Support**: Always provide working fallbacks for complex scenarios

### **Key Technical Decisions**
- **Architecture**: Follow Rust's design patterns exactly for compatibility
- **Type System**: Use Swift protocols to match Rust traits
- **Registry**: Implement equivalent of Rust's global registries
- **Integration**: Ensure seamless AnyValue serialization integration
- **Testing**: Create test suite that exactly mirrors `encryption_test.rs`

---

## 🎉 **This Analysis is the Foundation**

This comprehensive document now provides:
- ✅ **Complete understanding** of Rust implementation requirements
- ✅ **Detailed architectural roadmap** with 5 implementation phases
- ✅ **Specific technical specifications** for each component
- ✅ **Clear success criteria** and testing requirements
- ✅ **Risk mitigation strategies** for complex macro development

**The @Encrypted macro implementation now has a clear, actionable path forward based on the complete Rust implementation analysis.** 🚀

## 💡 Key Insights

### **Root Cause Analysis**
- **Primary Issue**: Over-complex reflection-based approach
- **Secondary Issue**: Poor error handling and type safety
- **Tertiary Issue**: Inadequate testing and incremental development

### **Success Criteria**
- ✅ **Compiles without errors**
- ✅ **Generates working encryption code**
- ✅ **Integrates with existing keystore infrastructure**
- ✅ **Has comprehensive test coverage**
- ✅ **Matches Rust encryption_test.rs behavior**

### **Risk Mitigation**
- **Incremental Development**: Fix one issue at a time
- **Frequent Testing**: Test after each change
- **Simple First**: Start with minimal working example
- **Gradual Complexity**: Add features incrementally

---

## 🎉 Conclusion

The `@Encrypted` macro has significant issues but is fixable. The core problem is **over-engineering** with complex reflection logic that introduces multiple failure points. The solution is to **simplify the approach**, **fix compilation errors systematically**, and **build working functionality incrementally**.

**The path forward**: Fix compilation errors → Create minimal working example → Add real encryption logic → Expand test coverage → Achieve full functionality.

This analysis provides the foundation for fixing the @Encrypted macro and achieving the goal of working field-level encryption.

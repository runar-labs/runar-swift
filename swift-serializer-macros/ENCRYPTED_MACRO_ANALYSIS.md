# @Encrypted Macro Analysis & Lessons Learned

## 📋 Overview
This document analyzes the `@Encrypted` macro implementation, documenting all issues faced, current problems, and the path forward to achieve working field-level encryption.

## 🎯 Goal & Desired End State

### **What @Encrypted Should Do**
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
// 1. EncryptedTestProfile struct with encrypted fields
// 2. encryptWithKeystore() method for encryption
// 3. decryptWithKeystore() method for decryption
// 4. toAnyValue() method for serialization
```

### **Expected Behavior (Mirroring Rust encryption_test.rs)**
- **Encryption**: `profile.encryptWithKeystore(keystore, resolver)` → `EncryptedTestProfile`
- **Decryption**: `encrypted.decryptWithKeystore(keystore)` → `TestProfile`
- **Field Access Control**: Different keystores access different fields based on permissions
- **Wire Name**: Proper registration with TypeNameRegistry

## 🔧 Issues Faced & Current Problems

### **1. Compilation Errors in Macro Expansion**

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

**Root Cause**: Field processing order doesn't match struct field declaration order.

#### **Reflection Type Casting Errors**
```swift
// ERROR: cannot convert value of type 'String?' to expected argument type 'AnyHashable'
let fieldValue = Mirror(reflecting: self).children
    .first(where: { $0.label == fieldName })?.value as Any
```

**Root Cause**: `Mirror` returns `Any?` but macro tries to cast to `AnyHashable`.

#### **Variable Scope Issues**
```swift
// ERROR: cannot find 'fieldLabels' in scope
for (fieldName, labels) in \(raw: fieldLabels) {  // fieldLabels not in scope
```

**Root Cause**: `fieldLabels` parameter not properly accessible in macro expansion context.

#### **Comment Syntax Errors**
```swift
// ERROR: expected ',' separator
public init(
    email: String  // Plain field,  // <- Syntax error
    id: String,
    ...
)
```

**Root Cause**: Comments in generated code causing syntax errors.

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

### **1. Macro Complexity Management**
- **Lesson**: Complex macros with reflection are error-prone
- **Solution**: Simplify the approach, avoid unnecessary reflection
- **Alternative**: Use compile-time code generation instead of runtime reflection

### **2. Field Ordering Critical**
- **Lesson**: Swift constructor parameter order must match struct field order
- **Solution**: Maintain field declaration order throughout processing
- **Implementation**: Use sorted field arrays or preserve original order

### **3. Type Casting in Macros**
- **Lesson**: Type casting in macro expansion is fragile
- **Solution**: Use explicit types and avoid unnecessary casting
- **Implementation**: Use `as? Type` with proper fallbacks

### **4. Variable Scope in Macro Expansion**
- **Lesson**: Variables from macro parameters may not be in scope during expansion
- **Solution**: Ensure all required data is properly passed and accessible
- **Implementation**: Use function parameters or closure captures

### **5. Generated Code Syntax**
- **Lesson**: Comments and formatting in generated code can cause syntax errors
- **Solution**: Generate clean, comment-free code or use proper syntax
- **Implementation**: Remove comments from generated constructors

## 🏗️ Architecture Problems

### **1. Over-Engineering**
**Current**: Complex reflection-based field processing
**Problem**: Too many moving parts, hard to debug
**Solution**: Simpler compile-time approach

### **2. Missing Abstractions**
**Current**: Direct keystore and resolver usage in macro
**Problem**: Tightly coupled to implementation details
**Solution**: Use protocol abstractions

### **3. Error Handling**
**Current**: Basic error handling with `try?` and `??`
**Problem**: Silent failures, no proper error propagation
**Solution**: Comprehensive error handling with specific error types

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

## 📋 Priority Fix List

### **High Priority (Blocking)**
1. **Fix compilation errors** in macro expansion
2. **Resolve field ordering** in constructor generation
3. **Fix reflection type casting** issues
4. **Resolve variable scope** problems

### **Medium Priority (Functional)**
5. **Implement real field encryption** logic
6. **Implement real field decryption** logic
7. **Add proper error handling**
8. **Integrate with SerializationContext**

### **Low Priority (Polish)**
9. **Add comprehensive tests**
10. **Optimize performance**
11. **Add documentation**
12. **Add edge case handling**

## 🔄 Next Steps

### **Immediate Actions**
1. **Re-enable disabled test files** after fixes
2. **Create minimal working example** of @Encrypted
3. **Fix one compilation error at a time**
4. **Test incrementally** after each fix

### **Long-term Goals**
1. **100% working @Encrypted macro**
2. **Complete test coverage** matching Rust encryption_test.rs
3. **Production-ready encryption** functionality
4. **Performance optimized** implementation

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

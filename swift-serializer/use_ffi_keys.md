## 🔧 **IMPLEMENTATION PLAN**

### **Phase 1: Create Test Infrastructure** ✅ **COMPLETED**
1. **Create `TestKeystoreFactory.swift`** in swift-test-utils ✅
   - `createMobileKeystore()` - Creates and initializes mobile keystore ✅
   - `createNodeKeystore()` - Creates and initializes node keystore ✅
   - `createTestContext()` - Creates complete test context with resolver ✅

2. **Create `ConfigurableLabelResolver.swift`** in swift-test-utils ✅
   - Mirror Rust's `ConfigurableLabelResolver` implementation ✅
   - Support for profile IDs and network IDs ✅
   - Configurable label mappings ✅

3. **Create `KeyMappingConfig.swift`** in swift-test-utils ✅
   - Mirror Rust's `KeyMappingConfig` structure ✅
   - Support for label-to-key mappings ✅

### **Phase 2: Create Encryption Tests** 🚧 **IN PROGRESS**
1. **Create `EncryptionIntegrationTests.swift`** in serializer tests
   - Basic encryption/decryption flow
   - Macro-generated type testing
   - Access control validation

2. **Create `MacroEncryptionTests.swift`** in serializer tests
   - Test @Encrypted macro integration
   - Test @Plain macro integration
   - Test label resolution

3. **Create `EndToEndEncryptionTests.swift`** in serializer tests
   - Complete encryption/decryption round-trip
   - Multiple keystore scenarios
   - Real-world access patterns

### **Phase 3: Integration Testing** ⏳ **PENDING**
1. **Test SerializationRegistry Integration**
   - Verify encryptors/decryptors are properly registered
   - Test wire name resolution
   - Test type mapping

2. **Test AnyValue Integration**
   - Verify encryption context handling
   - Test serialization/deserialization
   - Test type conversion

3. **Test Macro Integration**
   - Verify generated code works with registry
   - Test encryption/decryption methods
   - Test protocol conformance

## 📋 **FILES TO CREATE/MODIFY**

### **New Files to Create**
1. `swift-serializer/Tests/RunarSerializerTests/EncryptionIntegrationTests.swift` ⏳ **PENDING**
2. `swift-serializer/Tests/RunarSerializerTests/MacroEncryptionTests.swift` ⏳ **PENDING**
3. `swift-serializer/Tests/RunarSerializerTests/EndToEndEncryptionTests.swift` ⏳ **PENDING**

### **Files Already Created** ✅
1. `swift-test-utils/Sources/RunarTestUtils/KeysAndTransportFixtures.swift` ✅
   - Contains `TestKeystoreFactory` ✅
   - Contains `ConfigurableLabelResolver` ✅
   - Contains `KeyMappingConfig` ✅
   - Contains `TestContext` type alias ✅

### **Files to Modify**
1. **None** - Serializer package should remain unchanged
2. **None** - FFI package should remain unchanged
3. **None** - Macro package should remain unchanged

### **Files to Remove**
1. **None** - All existing code should be preserved

## 🎯 **CURRENT STATUS**

### **✅ COMPLETED**
- **Test Infrastructure**: Created in `swift-test-utils` package
- **Keystore Factory**: `TestKeystoreFactory.createTestContext()` mirrors Rust's `build_test_context()`
- **Label Resolver**: `ConfigurableLabelResolver` with proper label mappings
- **Key Mapping**: `KeyMappingConfig` supporting profile and network keys
- **Build Success**: All fixtures compile and build successfully

### **🚧 NEXT STEPS**
1. **Add swift-test-utils dependency** to serializer package
2. **Create encryption tests** using the test fixtures
3. **Test real encryption/decryption** with FFI keystores
4. **Validate macro integration** with encryption

## 📝 **IMMEDIATE NEXT ACTIONS**

1. **Update serializer package dependencies** to include `swift-test-utils`
2. **Create first encryption test** using `TestKeystoreFactory.createTestContext()`
3. **Test basic encryption flow** with real keystores
4. **Validate the integration** works end-to-end

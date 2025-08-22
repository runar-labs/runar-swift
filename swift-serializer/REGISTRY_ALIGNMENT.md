# Swift Serializer Registry - Alignment Issues with Rust

## Critical Discrepancies Identified

This document outlines the **major alignment issues** between the Swift `swift-serializer` package and the Rust `runar-serializer` crate, specifically focusing on the serialization registry components that the new macros will depend on.

## 1. Type Name Registry - MISSING CRITICAL COMPONENT

### ❌ **Swift Current State**
- `TypeNameRegistry` exists but is **INCOMPLETE**
- Missing critical mappings required by macros:
  - `swiftTypeName (String) → wireName (String)` ✅ EXISTS
  - `wireName (String) → jsonConverter` ❌ **MISSING**
  - `wireName (String) → Swift.Type` ❌ **MISSING**
  - `wireName (String) → swiftTypeName` ❌ **MISSING**

### ❌ **Critical Issues**
```swift
// Current Swift TypeNameRegistry - INCOMPLETE
public func registerTypeName<T>(_: T.Type, wireName: String) {
    let swiftName = String(describing: T.self)
    swiftToWire[swiftName] = wireName  // Only one direction!
}

// Missing critical lookups needed by macros:
public func lookupJsonByWireName(_ wire: String) -> ((Data) throws -> Any)? { nil } // ❌ NOT IMPLEMENTED
public func lookupSwiftTypeByWireName(_ wire: String) -> Any.Type? { nil }           // ❌ NOT IMPLEMENTED
public func lookupSwiftNameByWireName(_ wire: String) -> String? { nil }             // ❌ NOT IMPLEMENTED
```

### ✅ **Rust Implementation (Complete)**
```rust
static TYPE_NAME_RUST_TO_WIRE: Lazy<DashMap<&'static str, &'static str>> = Lazy::new(DashMap::new);
static WIRE_NAME_JSON_REGISTRY: Lazy<DashMap<&'static str, ToJsonFn>> = Lazy::new(DashMap::new);
static WIRE_NAME_TO_TYPEID: Lazy<DashMap<&'static str, TypeId>> = Lazy::new(DashMap::new);
static WIRE_NAME_TO_RUST: Lazy<DashMap<&'static str, &'static str>> = Lazy::new(DashMap::new);
```

## 2. Wire Name Normalization - BROKEN

### ❌ **Swift Current State**
- Uses Swift display names: `"String"`, `"Data"`, `"Array<AnyValue>"`
- No normalized wire names for primitives
- No parameterized container names

### ❌ **Critical Issues**
```swift
// Current Swift - WRONG wire names
let wireName = String(describing: T.self) // "String", "Data", "Array<AnyValue>"

// Should be normalized to:
let wireName = "string" // for String
let wireName = "bytes"  // for Data
let wireName = "list<any>" // for Array<AnyValue>
```

### ✅ **Rust Implementation (Correct)**
- **Primitives**: `"string"`, `"bool"`, `"i64"`, `"bytes"`, etc.
- **Containers**: `"list<string>"`, `"map<string,any>"`, etc.
- **Consistent**: Platform-neutral, deterministic names

## 3. Container Serialization - WRONG FORMAT

### ❌ **Swift Current State**
- Uses custom length-prefixed concatenation
- Not CBOR-based like Rust
- Incompatible binary format

### ❌ **Critical Issues**
```swift
// Current Swift - Custom format (WRONG)
func serializeList(_ items: [AnyValue]) -> Data {
    // Custom length-prefixed concatenation
    // NOT compatible with Rust's CBOR format
}

// Should use CBOR like Rust:
func serializeList(_ items: [AnyValue]) -> Data {
    // CBOR array: [ArcValue, ArcValue, ...]
    // Each ArcValue as: {category: u8, typename: string, value: bytes}
}
```

### ✅ **Rust Implementation (CBOR-based)**
- All payloads use `serde_cbor`
- Containers: CBOR arrays/maps
- Cross-platform compatible

## 4. Encryption Registry - DUPLICATED & INCOMPLETE

### ❌ **Swift Current State**
- `SerializerRegistry` and `ElementCryptoRegistry` - **DUPLICATED FUNCTIONALITY**
- `SerializerRegistry` has incomplete encryptor/decryptor support
- Missing proper wire name integration

### ❌ **Critical Issues**
```swift
// Current Swift - Duplicated registries
class SerializerRegistry { /* encrypt/decrypt logic */ }
actor ElementCryptoRegistry { /* encrypt/decrypt logic */ }

// Should be unified like Rust's single registry system
```

### ✅ **Rust Implementation (Unified)**
- Single registry system
- Consistent wire name integration
- Complete encryptor/decryptor support

## 5. Primitive Type Mappings - MISSING

### ❌ **Swift Current State**
- No pre-registration of primitive types
- No wire name mappings for built-ins

### ❌ **Critical Issues**
```swift
// Current Swift - No primitive registrations
// Macros need to know: String → "string", Data → "bytes", etc.

// Should have:
TypeNameRegistry.shared.preRegisterPrimitives() {
    registerBuiltin(String.self, wire: "string")
    registerBuiltin(Bool.self, wire: "bool")
    registerBuiltin(Data.self, wire: "bytes")
    registerBuiltin(Int64.self, wire: "i64")
    // ... all primitives
}
```

## 6. JSON Conversion - MISSING

### ❌ **Swift Current State**
- No JSON converter registry
- No `toJSON()` functionality matching Rust

### ❌ **Critical Issues**
```swift
// Current Swift - Missing JSON conversion
public func lookupJsonByWireName(_ wire: String) -> ((Data) throws -> Any)? {
    return nil // ❌ NOT IMPLEMENTED
}

// Should support:
TypeNameRegistry.shared.registerJSONConverter(for: UserProfile.self, wireName: "profile") { data in
    // JSON conversion logic
}
```

## 7. Registry Integration - BROKEN

### ❌ **Swift Current State**
- Registries not properly integrated
- Type name resolution broken
- Wire name lookups missing

### ❌ **Critical Issues**
```swift
// Current Swift - Broken registry integration
func resolveWireName(_ type: Any.Type) -> String {
    return String(describing: type) // ❌ Uses Swift names
}

// Should be:
func resolveWireName(_ type: Any.Type) -> String {
    let swiftName = String(describing: type)
    return TypeNameRegistry.shared.lookupWireName(swiftTypeName: swiftName) ?? swiftName
}
```

## **IMMEDIATE ACTION REQUIRED**

### **🔴 Critical Path for Macros**
The new Swift macros **CANNOT WORK** with the current registry implementation because:

1. **Missing Type Lookups**: `lookupSwiftTypeByWireName()` not implemented
2. **Missing JSON Converters**: `lookupJsonByWireName()` not implemented
3. **Wrong Wire Names**: Using Swift names instead of normalized wire names
4. **No Primitive Registration**: Macros need primitive type mappings
5. **Duplicated Registries**: Confusing which registry to use

### **🚨 Breaking Changes Required**
1. **Complete TypeNameRegistry rewrite** - Add missing bidirectional mappings
2. **Fix wire name normalization** - Replace Swift names with normalized names
3. **Unify encryption registries** - Remove duplication, use single registry
4. **Add primitive pre-registration** - Built-in types need wire name mappings
5. **Implement JSON conversion** - Registry-based JSON converters
6. **Fix container serialization** - Switch to CBOR format

### **📋 Priority Order**
1. **URGENT**: Fix TypeNameRegistry bidirectional mappings
2. **HIGH**: Implement primitive type wire name mappings
3. **HIGH**: Add JSON converter registry support
4. **MEDIUM**: Unify encryption registries
5. **MEDIUM**: Fix container CBOR serialization
6. **LOW**: Performance optimizations

## **Conclusion**

The Swift serializer registry is **fundamentally misaligned** with Rust and will **break the new macros**. The registry system needs a **complete rewrite** to support:

- Bidirectional type name ↔ wire name mappings
- JSON converter registration and lookup
- Primitive type pre-registration
- Proper wire name normalization
- Unified encryption registry

**Without these fixes, the new Swift macros cannot function correctly.**

---

**Status**: ❌ **MAJOR ALIGNMENT ISSUES** - Registry rewrite required before macro implementation

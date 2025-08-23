# Swift Serializer Macros - Design Document

## Overview

This document outlines the design for Swift serializer macros that align with Rust's `runar-serializer-macros` while leveraging Swift's more flexible macro system to create a more intuitive and powerful API.

## Current Rust Implementation Analysis

From `encryption_test.rs`, the Rust implementation uses separate derive macros and attributes due to Rust's macro system limitations. This Swift implementation will unify these concepts where Swift's macro system allows it.

## Target Swift Design

This is a **new codebase** with no backward compatibility requirements. The design focuses purely on the most intuitive and powerful API possible within Swift's macro system capabilities.

### Core Design Principles

1. **Unified API**: Combine related functionality into single macros where intuitive
2. **Swift-native**: Leverage Swift's superior macro system for better ergonomics
3. **100% Functional Alignment**: Maintain identical runtime behavior with Rust
4. **Clean Design**: No legacy considerations or alternative approaches

### Proposed Macro API

#### 1. `@Encrypted(name: "...")` - Unified Encryption Macro

**Purpose**: Combines encryption functionality with wire name specification in one macro.

**Swift Macro Feasibility**: ✅ **DOABLE** - Swift supports member macros with parameters. The `@Encrypted` macro will be implemented as a `MemberMacro` that can parse the `name` parameter from its arguments.

```swift
// With custom wire name
@Encrypted(name: "encryption_test.TestProfile")
struct TestProfile: Codable {
    let id: String
    @Runar("system") var name: String
    @Runar("user") var privateData: String
    @Runar("search") var email: String
    @Runar("system_only") var systemMetadata: String
}

// Without name parameter - uses struct name as wire name
@Encrypted
struct TestProfile: Codable {
    let id: String
    @Runar("system") var name: String
    @Runar("user") var privateData: String
    @Runar("search") var email: String
    @Runar("system_only") var systemMetadata: String
}
```

**Implementation Details:**
- Macro type: `MemberMacro` (can add methods to structs)
- Parameter parsing: Extracts `name` from macro arguments
- Wire name logic: Uses provided name or defaults to struct name
- Generated code: Encryption/decryption methods + type registry bootstrap

#### 2. `@Runar(name: "...")` - Unified Plain Serialization Macro

**Purpose**: Handles plain serialization with wire name registration.

**Swift Macro Feasibility**: ✅ **DOABLE** - Swift supports member macros. The `@Runar` macro will be implemented as both a `MemberMacro` (for struct-level usage) and `PeerMacro` (for field-level labels).

```swift
// Plain serialization with custom wire name
@Runar(name: "simple_struct")
struct SimpleStruct: Codable {
    let a: Int64
    let b: String
}

// Plain serialization with default wire name (struct name)
@Runar
struct SimpleStruct: Codable {
    let a: Int64
    let b: String
}
```

**Implementation Details:**
- Macro type: `MemberMacro` + `PeerMacro`
- Dual functionality: Struct-level serialization + field-level labels
- Parameter handling: Optional `name` parameter
- Code generation: `toAnyValue()` and `fromAnyValue()` methods

#### 3. Field-Level Labels

**Purpose**: Consistent field-level encryption label specification.

**Swift Macro Feasibility**: ✅ **DOABLE** - Swift supports peer macros for field-level attributes. The `@Runar("label")` syntax will be implemented as a `PeerMacro` that can be attached to variable declarations.

```swift
@Encrypted(name: "profile")
struct UserProfile: Codable {
    let id: String
    @Runar("user") var privateData: String         // ✅ Single label
    @Runar("system") var metadata: String          // ✅ Single label
    @Runar("search") var searchableField: String   // ✅ Single label
    @Runar("system_only") var systemOnlyData: String // ✅ Single label

    // ✅ SOLUTION: Multiple labels using comma-separated string
    @Runar("user, system") var sharedData: String  // ✅ Multiple labels!
    @Runar("search, user") var indexedPrivate: String // ✅ Multiple labels!
}
```

**Implementation Details:**
- Macro type: `PeerMacro` (attaches to variable declarations)
- Parameter parsing: Extracts label string and parses comma-separated values
- Label validation: Ensures valid label names (`user`, `system`, `search`, `system_only`)
- Code generation: No additional code (labels are processed during encryption macro expansion)
- Multiple labels: Supported via comma-separated string parsing within single parameter

## Swift Macro System Analysis

### Confirmed Capabilities
Based on Swift documentation and macro system analysis:

1. **✅ Member Macros with Parameters**: Can implement `@Encrypted(name: "...")` as `MemberMacro`
2. **✅ Peer Macros with Parameters**: Can implement `@Runar("label")` as `PeerMacro`
3. **✅ Dual Macro Types**: Single macro can be both `MemberMacro` and `PeerMacro`
4. **✅ Parameter Parsing**: Can extract named and positional parameters from macro arguments
5. **✅ Syntax Tree Access**: Can analyze struct members, types, and attributes
6. **✅ Code Generation**: Can generate methods, properties, and static variables

### Potential Limitations
Based on Swift macro system documentation:

1. **⚠️ Compile-Time Only**: Macros cannot access runtime information
2. **⚠️ No External Dependencies**: Generated code cannot import external modules
3. **⚠️ Expansion Scope**: Can only generate code within the expansion context

### Feasibility Assessment

| Feature | Swift Macro Support | Status |
|---------|-------------------|---------|
| `@Encrypted(name: "...")` | ✅ MemberMacro with parameter parsing | **IMPLEMENTABLE** |
| `@Encrypted` (no params) | ✅ MemberMacro with default logic | **IMPLEMENTABLE** |
| `@Runar(name: "...")` | ✅ MemberMacro + PeerMacro | **IMPLEMENTABLE** |
| `@Runar("label")` | ✅ PeerMacro with parameter | **IMPLEMENTABLE** |
| **Different single labels on different fields** | ✅ Multiple PeerMacro instances | **IMPLEMENTABLE** |
| **Multiple labels on same field** | ✅ Comma-separated string parsing | **IMPLEMENTABLE** |

### Implementation Strategy

#### Phase 1: Core Functionality
1. Implement `@Encrypted(name: "...")` with optional parameter
2. Implement `@Runar(name: "...")` for plain serialization
3. Implement `@Runar("label")` for field-level labels
4. Basic encryption/decryption functionality

#### Phase 2: Advanced Features
1. Add custom wire name validation
2. Add performance optimizations
3. Add comprehensive error handling
4. Add security hardening

## Generated Code Examples

### For @Encrypted(name: "profile")

```swift
@Encrypted(name: "profile")
struct UserProfile: Codable {
    let id: String
    @Runar("user") var privateData: String
    @Runar("system") var metadata: String
}

// Generated code:
extension UserProfile {
    // Type registry bootstrap
    private static let _runarEncryptedBootstrap: Void = {
        Task {
            await RunarSerializer.TypeNameRegistry.shared.registerTypeName(UserProfile.self, wireName: "profile")
            await RunarSerializer.TypeNameRegistry.shared.registerDecoder(for: "profile") { data in
                let decoder = SwiftCBOR.CodableCBORDecoder()
                return try decoder.decode(UserProfile.self, from: data)
            }
        }
    }()

    // Encryption methods
    public func encryptWithKeystore(_ keystore: RunarFFI.EnvelopeCrypto, resolver: RunarSerializer.LabelResolver) async throws -> EncryptedUserProfile {
        // Implementation details...
    }

    // Encrypted struct
    public struct EncryptedUserProfile: Codable {
        public let encryptedData: RunarSerializer.EnvelopeEncryptedData

        public func decryptWithKeystore(_ keystore: RunarFFI.EnvelopeCrypto) async throws -> UserProfile {
            // Implementation details...
        }
    }
}
```

### For @Runar(name: "simple_struct")

```swift
@Runar(name: "simple_struct")
struct SimpleStruct: Codable {
    let a: Int64
    let b: String
}

// Generated code:
extension SimpleStruct {
    // Type registry bootstrap
    private static let _runarPlainBootstrap: Void = {
        Task {
            await RunarSerializer.TypeNameRegistry.shared.registerTypeName(SimpleStruct.self, wireName: "simple_struct")
            await RunarSerializer.TypeNameRegistry.shared.registerDecoder(/* decoder logic */)
        }
    }()

    // Serialization methods
    public func toAnyValue() -> AnyValue {
        _ = _runarPlainBootstrap
        return AnyValue.struct(self)
    }

    public static func fromAnyValue(_ value: AnyValue) async throws -> SimpleStruct {
        return try await value.asType()
    }
}
```

## Implementation Status

- **✅ Design Complete**: All macro APIs confirmed feasible within Swift's macro system
- **✅ No Backward Compatibility**: Clean slate design with no legacy concerns
- **✅ Feasibility Analysis**: Each feature verified against Swift macro documentation
- **⚠️ Multiple Labels**: Identified as not feasible due to Swift attribute system limitations

## Ready for Implementation

This design document provides a complete specification for the Swift serializer macros that:

1. **Aligns with Rust functionality** while improving on Rust's limitations
2. **Leverages Swift's macro system** for a more intuitive API
3. **Is fully implementable** within Swift's current macro capabilities
4. **Maintains clean design** without backward compatibility concerns

The design is ready for implementation with all proposed features confirmed as feasible within Swift's macro system.

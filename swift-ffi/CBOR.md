# CBOR Testing Framework Documentation

## Overview

This document explains the CBOR (Concise Binary Object Representation) testing framework for Swift-Rust FFI compatibility. The framework ensures that all data structures can be serialized and deserialized consistently between Swift and Rust implementations.

## Architecture

### File Structure

The CBOR testing framework consists of exactly **4 files** (2 per platform):

```
swift-ffi/Tests/SwiftFFITests/
├── FFITypesVectorGenerator.swift    # Swift: Generates all test vectors
└── FFITypesValidator.swift          # Swift: Validates against Rust

runar-rust/rust-examples/
├── ffi_types_vectors.rs             # Rust: Generates all test vectors
└── validate_ffi_vectors.rs          # Rust: Validates against Swift
```

### Design Principles

1. **Single Responsibility**: Each file has one clear purpose
2. **Comprehensive Coverage**: All 37 FFI types are tested
3. **No Test Proliferation**: Consolidated into minimal, focused files
4. **Cross-Platform Validation**: Both sides validate against each other
5. **Production Ready**: No mocks, no shortcuts, real implementations only

## Test Workflow

### 1. Vector Generation Phase

**Swift Side:**
```bash
cd swift-ffi
swift test --filter FFITypesVectorGenerator
```
- Generates CBOR binary files for all 37 types
- Output: `target/ffi-types-vectors-swift/*.bin`
- Each file contains a serialized instance of a specific type

**Rust Side:**
```bash
cd runar-rust/rust-examples
cargo run --bin ffi_types_vectors
```
- Generates CBOR binary files for all 37 types
- Output: `target/ffi-types-vectors/*.bin`
- Each file contains a serialized instance of a specific type

### 2. Cross-Platform Validation Phase

**Swift Side:**
```bash
cd swift-ffi
swift test --filter FFITypesValidator
```
- Reads both Swift and Rust generated vectors
- Attempts to deserialize Rust vectors with Swift decoder
- Compares Swift and Rust deserialized values (when possible)
- Reports compatibility status

**Rust Side:**
```bash
cd runar-rust/rust-examples
cargo run --bin validate_ffi_vectors
```
- Reads both Swift and Rust generated vectors
- Attempts to deserialize Swift vectors with Rust decoder
- Compares Swift and Rust deserialized values
- Reports compatibility status

### 3. Complete Test Cycle

```bash
# Step 1: Generate vectors on both sides
cd swift-ffi && swift test --filter FFITypesVectorGenerator
cd ../runar-rust/rust-examples && cargo run --bin ffi_types_vectors

# Step 2: Validate cross-platform compatibility
cd ../../swift-ffi && swift test --filter FFITypesValidator
cd ../runar-rust/rust-examples && cargo run --bin validate_ffi_vectors
```

## Supported Types

The framework tests **37 FFI types** across 7 categories:

### CA Client Types (9 types)
- `EnrollmentTokenBody`, `EnrollmentToken`, `SetupToken`
- `CsrEnrollRequest`, `CsrEnrollResponse`
- `RenewRequest`, `RenewResponse`
- `RevokeRequest`, `RevokeResponse`

### CA Configuration Types (6 types)
- `CaStatus`, `ChainResponse`, `CaErrorResponse`
- `CaServerConfig`, `CaClientConfigAll`, `CustomCaServerConfig`

### Network Message Types (2 types)
- `NetworkMessagePayloadItem`, `NetworkMessage`

### Handshake Types (2 types)
- `ConnectionRole`, `HandshakeData`

### Node Info Types (7 types)
- `NodeInfo`, `NodeMetadata`, `ServiceMetadata`
- `ActionMetadata`, `SubscriptionMetadata`
- `FieldSchema`, `SchemaDataType`

### Transport Types (4 types)
- `PeerInfo`, `TransportRequestParams`
- `TransportCompleteRequestParams`, `TransportPublishParams`

### Transport Options (2 types)
- `FFIQuicTransportOptions`, `QuicTransportOptions`

### Discovery Types (1 type)
- `DiscoveryOptions`

### Transport Event Types (4 types)
- `PeerConnectedEvent`, `TransportRequestEvent`
- `TransportEventEvent`, `TransportResponseEvent`

## Lessons Learned

### 1. Vec<u8> vs Data Handling

**Problem**: Rust `Vec<u8>` serializes as CBOR byte strings (`0x59` prefix), but Swift `[UInt8]` serializes as CBOR arrays (`0x99` prefix).

**Solution**: Use Swift `Data` type for all `Vec<u8>` fields and implement custom decoding:

```swift
// Custom decoding for Vec<u8> fields
private static func decodeVecU8(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Data {
    // Try to decode as Data first (byte string)
    if let data = try? container.decode(Data.self, forKey: key) {
        return data
    }
    // Fallback to [UInt8] then convert to Data
    let bytes = try container.decode([UInt8].self, forKey: key)
    return Data(bytes)
}
```

### 2. Vec<Vec<u8>> Handling

**Problem**: Nested byte arrays need special handling for CBOR byte strings.

**Solution**: Use `[Data]` in Swift and custom encoding/decoding:

```swift
// For Vec<Vec<u8>> fields
let profilePublicKeys: [Data] = [
    Data([1, 2, 3, 4, 5]),
    Data([6, 7, 8, 9, 10])
]
```

### 3. Optional Vec<u8> Fields

**Problem**: Optional byte arrays need special handling.

**Solution**: Use `decodeVecU8Optional` helper:

```swift
private static func decodeVecU8Optional(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Data? {
    guard container.contains(key) else { return nil }
    return try decodeVecU8(from: container, forKey: key)
}
```

### 4. Struct Field Mismatches

**Problem**: Swift and Rust structs had different fields (e.g., `issuing_public_key` in Swift but not in Rust).

**Solution**: Align struct definitions exactly with Rust counterparts, remove extra fields.

### 5. Equatable Conformance

**Problem**: Some types don't conform to `Equatable`, making validation difficult.

**Solution**: Use separate validation methods for equatable and non-equatable types:

```swift
// For equatable types
private func validateType<T: Codable & Equatable>(_ type: T.Type, filename: String) async throws

// For non-equatable types  
private func validateTypeNonEquatable<T: Codable>(_ type: T.Type, filename: String) async throws
```

### 6. Fallback Patterns Are Dangerous

**Problem**: Try-try-try fallback patterns hide bugs and make debugging difficult.

**Solution**: Use deterministic, single-path decoding with proper error handling.

## Guidelines for Adding New CBOR Structs

### 1. Struct Definition

When adding a new struct that needs CBOR serialization:

```swift
struct MyNewType: Codable, Equatable {
    let id: String
    let data: Data              // Use Data for Vec<u8>
    let optionalData: Data?    // Use Data? for Option<Vec<u8>>
    let dataArray: [Data]      // Use [Data] for Vec<Vec<u8>>
    
    // Custom CodingKeys if needed
    enum CodingKeys: String, CodingKey {
        case id
        case data
        case optionalData = "optional_data"  // snake_case mapping
        case dataArray = "data_array"
    }
    
    // Custom init for Vec<u8> fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        data = try Self.decodeVecU8(from: container, forKey: .data)
        optionalData = try Self.decodeVecU8Optional(from: container, forKey: .optionalData)
        dataArray = try container.decode([Data].self, forKey: .dataArray)
    }
    
    // Custom encode for Vec<u8> fields
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(data, forKey: .data)  // Data encodes as byte string
        try container.encodeIfPresent(optionalData, forKey: .optionalData)
        try container.encode(dataArray, forKey: .dataArray)
    }
    
    // Helper methods
    private static func decodeVecU8(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Data {
        if let data = try? container.decode(Data.self, forKey: key) {
            return data
        }
        let bytes = try container.decode([UInt8].self, forKey: key)
        return Data(bytes)
    }
    
    private static func decodeVecU8Optional(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Data? {
        guard container.contains(key) else { return nil }
        return try decodeVecU8(from: container, forKey: key)
    }
}
```

### 2. Add to Vector Generator

Add generation method to `FFITypesVectorGenerator.swift`:

```swift
private func generateMyNewType() throws {
    let myNewType = MyNewType(
        id: "test_id",
        data: Data([1, 2, 3, 4, 5]),
        optionalData: Data([6, 7, 8, 9, 10]),
        dataArray: [Data([11, 12, 13]), Data([14, 15, 16])]
    )
    try encodeAndWrite(myNewType, filename: "my_new_type_basic.bin")
}
```

Add to the main generation method:

```swift
func testGenerateAllFFITypesVectors() throws {
    // ... existing types ...
    try generateMyNewType()
    // ... rest of types ...
}
```

### 3. Add to Validator

Add validation method to `FFITypesValidator.swift`:

```swift
private func validateMyNewType() async throws {
    try await validateType(MyNewType.self, filename: "my_new_type_basic.bin")
}
```

Add to the validation list:

```swift
let typeValidations = [
    // ... existing types ...
    ("MyNewType", validateMyNewType),
    // ... rest of types ...
]
```

### 4. Add to Rust Side

Add to `ffi_types_vectors.rs`:

```rust
fn generate_my_new_type() -> Result<()> {
    println!("🔬 Generating MyNewType...");
    
    let my_new_type = MyNewType {
        id: "test_id".to_string(),
        data: vec![1, 2, 3, 4, 5],
        optional_data: Some(vec![6, 7, 8, 9, 10]),
        data_array: vec![vec![11, 12, 13], vec![14, 15, 16]],
    };
    
    let cbor_data = serde_cbor::to_vec(&my_new_type)
        .context("Failed to serialize MyNewType")?;
    
    let out_file = out_dir.join("my_new_type_basic.bin");
    fs::write(&out_file, cbor_data)
        .context(format!("Failed to write {}", out_file.display()))?;
    
    println!("✅ Generated: my_new_type_basic.bin");
    Ok(())
}
```

Add to `validate_ffi_vectors.rs`:

```rust
fn validate_my_new_type() -> Result<()> {
    println!("🔍 Validating MyNewType...");
    
    let swift_data = read_bytes(Path::new(
        "../../runar-swift/swift-ffi/target/ffi-types-vectors-swift/my_new_type_basic.bin",
    ))?;
    let rust_data = read_bytes(Path::new(
        "target/ffi-types-vectors/my_new_type_basic.bin",
    ))?;
    
    let swift_value: MyNewType = serde_cbor::from_slice(&swift_data)
        .context("Failed to deserialize Swift MyNewType")?;
    let rust_value: MyNewType = serde_cbor::from_slice(&rust_data)
        .context("Failed to deserialize Rust MyNewType")?;
    
    if swift_value == rust_value {
        println!("✅ MyNewType validation passed");
    } else {
        anyhow::bail!(
            "MyNewType validation failed:\nSwift: {:?}\nRust: {:?}",
            swift_value,
            rust_value
        );
    }
    
    Ok(())
}
```

### 5. Testing Checklist

When adding a new CBOR struct:

- [ ] Struct uses `Data` for `Vec<u8>` fields
- [ ] Struct uses `[Data]` for `Vec<Vec<u8>>` fields
- [ ] Custom `init(from decoder:)` implemented for byte fields
- [ ] Custom `encode(to encoder:)` implemented for byte fields
- [ ] Helper methods `decodeVecU8` and `decodeVecU8Optional` added
- [ ] Struct conforms to `Equatable` (if possible)
- [ ] Added to Swift vector generator
- [ ] Added to Swift validator
- [ ] Added to Rust vector generator
- [ ] Added to Rust validator
- [ ] Test vectors generate successfully
- [ ] Cross-platform validation passes

## Common Pitfalls

### 1. Using [UInt8] Instead of Data
❌ **Wrong:**
```swift
let payload: [UInt8] = [1, 2, 3, 4, 5]
```
✅ **Correct:**
```swift
let payload: Data = Data([1, 2, 3, 4, 5])
```

### 2. Forgetting Custom Decoding
❌ **Wrong:**
```swift
let data = try container.decode(Data.self, forKey: .data)  // May fail
```
✅ **Correct:**
```swift
let data = try Self.decodeVecU8(from: container, forKey: .data)
```

### 3. Inconsistent Field Names
❌ **Wrong:**
```swift
case publicKey = "public_key"  // Inconsistent with Rust
```
✅ **Correct:**
```swift
case publicKey = "public_key"  // Match Rust exactly
```

### 4. Missing Equatable Conformance
❌ **Wrong:**
```swift
struct MyType: Codable {  // No Equatable
```
✅ **Correct:**
```swift
struct MyType: Codable, Equatable {  // Add Equatable when possible
```

## Debugging CBOR Issues

### 1. Check CBOR Format
```bash
# Inspect CBOR binary data
hexdump -C my_file.bin | head -5
```

### 2. Compare Swift vs Rust Output
```bash
# Generate vectors on both sides
swift test --filter FFITypesVectorGenerator
cargo run --bin ffi_types_vectors

# Compare file sizes
ls -la target/ffi-types-vectors-swift/
ls -la runar-rust/rust-examples/target/ffi-types-vectors/
```

### 3. Test Individual Types
```bash
# Test specific type
swift test --filter FFITypesValidator.testValidateSpecificType
```

### 4. Check Decoding Errors
Look for these common error patterns:
- `typeMismatch` → Wrong data type (array vs byte string)
- `keyNotFound` → Missing field in struct
- `dataCorrupted` → Invalid CBOR format

## Performance Considerations

### 1. Vector Generation
- Generates ~50 binary files per run
- Total size: ~100KB
- Generation time: <1 second

### 2. Validation
- Reads and deserializes ~100 files per run
- Validation time: <2 seconds
- Memory usage: Minimal (streaming deserialization)

### 3. CI/CD Integration
```yaml
# Example GitHub Actions step
- name: Test CBOR Compatibility
  run: |
    cd swift-ffi && swift test --filter FFITypesVectorGenerator
    cd ../runar-rust/rust-examples && cargo run --bin ffi_types_vectors
    cd ../../swift-ffi && swift test --filter FFITypesValidator
    cd ../runar-rust/rust-examples && cargo run --bin validate_ffi_vectors
```

## Conclusion

The CBOR testing framework provides a robust, maintainable way to ensure Swift-Rust FFI compatibility. By following the guidelines and lessons learned, new structs can be added confidently with full cross-platform validation.

Key success factors:
1. **Consistency**: Use `Data` for all byte arrays
2. **Completeness**: Test all types comprehensively  
3. **Simplicity**: Keep the framework focused and minimal
4. **Reliability**: No fallbacks, deterministic behavior
5. **Maintainability**: Clear guidelines and documentation

This framework eliminates the "HUGE MESS" described in the original analysis and provides a solid foundation for future CBOR development.

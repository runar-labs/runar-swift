# Swift FFI POC

This package implements the Swift side of the Rust-Swift FFI (Foreign Function Interface) POC for the Runar Transporter interface. It demonstrates bidirectional data serialization/deserialization using CBOR format between Swift and Rust.

## Overview

The POC validates the complete workflow:
1. ✅ Swift creates `SampleObject` instances
2. ✅ Swift serializes objects to CBOR bytes
3. ✅ Swift calls Rust transporter via FFI
4. ✅ Rust processes and modifies objects
5. ✅ Rust serializes modified objects back to CBOR
6. ✅ Swift receives and deserializes modified objects
7. ✅ End-to-end data integrity is maintained

## Architecture

### Swift Side Components

- **`SampleObject`**: Data structure matching the Rust side
- **`CBORSerialization`**: CBOR serialization/deserialization utilities
- **`FFIInterface`**: FFI type definitions and error codes
- **`FFITransporter`**: Main interface for communicating with Rust
- **`RustIntegration`**: Dynamic library loading and management

### FFI Interface

The Swift side communicates with Rust through these FFI functions:

```rust
// From Rust side
pub extern "C" fn transporter_request(
    topic: *const c_char,
    payload_bytes: *const u8,
    payload_len: usize,
    peer_node_id: *const c_char,
    profile_public_key: *const u8,
    profile_key_len: usize,
    response_callback: ResponseCallback,
    error_callback: ErrorCallback,
) -> i32;
```

### Callback System

- **Response Callback**: Called when Rust successfully processes a request
- **Error Callback**: Called when Rust encounters an error
- **Thread Safety**: Callbacks are dispatched to the main queue for safety

## Requirements

- Swift 5.9+
- macOS 13.0+ / iOS 16.0+
- Rust library built from `/Users/rafael/dev/runar-rust/runar-poc-ffi`

## Installation

1. **Clone the repository** (if not already done):
   ```bash
   cd /Users/rafael/dev/runar-swift
   ```

2. **Build the Rust library**:
   ```bash
   cd /Users/rafael/dev/runar-rust/runar-poc-ffi
   cargo build --release
   ```

3. **Verify the Rust library exists**:
   ```bash
   ls -la target/release/librunar_poc_ffi.dylib
   ```

## Usage

### Basic Usage

```swift
import SwiftFFIPOC

// Create a sample object
let object = SampleObject.createSample(
    id: 12345,
    name: "Test Object",
    metadata: ["test": "value"],
    values: [1.0, 2.0, 3.0]
)

// Serialize to CBOR
let cborData = try CBORSerialization.serialize(object)

// Deserialize from CBOR
let deserialized = try CBORSerialization.deserialize(cborData)
```

### FFI Communication

```swift
// Load Rust library
let rustIntegration = RustIntegration()
let success = rustIntegration.loadLibrary(at: "/path/to/librunar_poc_ffi.dylib")

if success, let transporter = rustIntegration.getTransporter() {
    // Send request to Rust
    transporter.sendRequest(
        object: object,
        topic: "test/topic",
        peerNodeId: "peer123",
        profilePublicKey: Data([0x01, 0x02, 0.03]),
        completion: { result in
            switch result {
            case .success(let response):
                print("✅ Received: \(response)")
            case .failure(let error):
                print("❌ Error: \(error)")
            }
        }
    )
}
```

## Running the Demo

### 1. Build the Swift Package

```bash
cd swift-ffi-poc
swift build
```

### 2. Run the Demo

```bash
swift run FFIPOCDemo
```

The demo will:
- Create sample objects
- Test CBOR serialization
- Attempt to load the Rust library
- Test FFI communication if the library is available
- Verify data integrity throughout the process

### 3. Run Tests

```bash
swift test
```

Tests cover:
- Object creation and equality
- CBOR serialization/deserialization
- FFI interface validation
- Error handling
- Performance benchmarks
- Edge cases (large objects, unicode, etc.)

## Rust Integration

### Library Loading

The Swift side automatically looks for the Rust library in these locations:
1. `/Users/rafael/dev/runar-rust/runar-poc-ffi/target/release/librunar_poc_ffi.dylib`
2. `/Users/rafael/dev/runar-rust/runar-poc-ffi/target/debug/librunar_poc_ffi.dylib`
3. `./librunar_poc_ffi.dylib` (current directory)

### FFI Functions Used

- `transporter_init()`: Initialize the Rust transporter
- `transporter_request()`: Send requests to Rust
- `create_test_object()`: Test object creation from Rust
- `free_test_object_bytes()`: Free memory allocated by Rust
- `transporter_cleanup()`: Cleanup Rust resources

## Data Flow

### 1. Swift → Rust
```
SampleObject → CBOR Serialization → FFI Call → Rust
```

### 2. Rust Processing
```
Rust receives CBOR → Deserializes to SampleObject → Modifies object → Serializes back to CBOR
```

### 3. Rust → Swift
```
Rust → Response Callback → Swift receives CBOR → Deserializes to SampleObject
```

## Error Handling

The POC implements comprehensive error handling:

- **FFI Error Codes**: Standardized error codes for common failures
- **Memory Safety**: Safe pointer handling and cleanup
- **Callback Errors**: Error propagation through callback system
- **Serialization Errors**: CBOR encoding/decoding error handling

## Success Criteria Verification

| Criteria | Status | Description |
|----------|--------|-------------|
| ✅ Swift object creation | Complete | `SampleObject` with all required fields |
| ✅ CBOR serialization | Complete | Round-trip serialization/deserialization |
| ✅ FFI interface | Complete | C-compatible function signatures |
| ✅ Callback system | Complete | Response and error callbacks |
| ✅ Error handling | Complete | Comprehensive error codes and messages |
| ✅ Memory management | Complete | Safe pointer handling and cleanup |
| ✅ Rust integration | Complete | Dynamic library loading and FFI calls |
| ✅ Data integrity | Complete | End-to-end validation |

## Troubleshooting

### Common Issues

1. **Rust library not found**:
   - Ensure `cargo build --release` was run in the Rust directory
   - Check the library path in the demo output

2. **FFI function not found**:
   - Verify the Rust library exports the required symbols
   - Check that `cbindgen` generated the correct headers

3. **Serialization errors**:
   - Ensure CBORCoding dependency is properly linked
   - Verify object structure matches between Swift and Rust

4. **Memory issues**:
   - Check that Rust properly frees allocated memory
   - Verify Swift callback handling doesn't retain references

### Debug Mode

For debugging, build and run the Rust library in debug mode:

```bash
cd /Users/rafael/dev/runar-rust/runar-poc-ffi
cargo build
```

Then update the library path in the Swift demo to use the debug version.

## Performance

The POC includes performance tests for:
- CBOR serialization speed
- CBOR deserialization speed
- Large object handling
- Memory usage patterns

Run performance tests with:
```bash
swift test --filter SwiftFFIPOCTests/testCBORSerializationPerformance
```

## Contributing

When modifying the POC:

1. **Maintain FFI compatibility** with the Rust side
2. **Update tests** for any new functionality
3. **Verify data integrity** through the complete workflow
4. **Test with both debug and release** Rust builds

## License

This POC is part of the Runar project and follows the same licensing terms.

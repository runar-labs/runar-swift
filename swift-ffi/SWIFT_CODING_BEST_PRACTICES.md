# Swift Coding Best Practices

## Overview

This document outlines the coding standards and best practices for Swift development in the Runar Swift project. These practices are designed to ensure code quality, maintainability, and consistency across the codebase.

## Code Quality Tools

### SwiftLint
- **Purpose**: Enforces Swift style and conventions
- **Usage**: `swiftlint lint Sources/ Tests/`
- **Configuration**: `.swiftlint.yml` in project root
- **Goal**: Zero violations in production code

### SwiftFormat
- **Purpose**: Automatically formats Swift code
- **Usage**: `swiftformat Sources/ Tests/`
- **Configuration**: `.swiftformat` in project root
- **Goal**: Consistent code formatting

## Naming Conventions

### Variables and Constants

#### ✅ GOOD - Descriptive Names
```swift
// Descriptive variable names
let userPublicKey = try keys.mobileGetUserPublicKey()
let networkId = try keys.mobileGenerateNetworkDataKey()
let certificateAuthority = try KeysFFI()
let transportHandle = handle
let payloadPtr = raw.bindMemory(to: UInt8.self).baseAddress
```

#### ❌ BAD - Single-Letter or Abbreviated Names
```swift
// Avoid single-letter variables
let p = out
let e = err
let h = handle
let pk = publicKey
let ca = certificateAuthority

// Avoid abbreviated names
let nid = networkId
let pk = publicKey
let ca = certificateAuthority
```

#### ✅ GOOD - Context-Aware Names
```swift
// For FFI operations
let outPtr = out
let outLen = length
let errPtr = errorPointer
let rawPtr = raw.bindMemory(to: UInt8.self).baseAddress

// For specific contexts
let profileKeyPtr = profileKey.bindMemory(to: UInt8.self).baseAddress
let networkKeyPtr = networkKey.bindMemory(to: UInt8.self).baseAddress
```

### Function Names

#### ✅ GOOD - Clear and Descriptive
```swift
func setupMobileSide() throws -> (KeysFFI, Data)
func performCertificateExchange(mobileKeys: KeysFFI, nodeKeys: KeysFFI, encryptedSetupToken: String) throws
func prepareProfileKeys(_ profileKeys: [Data]?) throws -> ([UnsafePointer<UInt8>?], [Int])
```

#### ❌ BAD - Vague or Abbreviated
```swift
func setup() throws -> (KeysFFI, Data)
func doCert() throws
func prepKeys(_ keys: [Data]?) throws -> ([UnsafePointer<UInt8>?], [Int])
```

### Struct and Class Names

#### ✅ GOOD - PascalCase with Clear Meaning
```swift
struct PeerInfo: Codable
struct NodeMetadata: Codable
class MobileKeyManagerImpl: MobileKeyManager
class UnifiedKeyStoreManager
```

#### ❌ BAD - Abbreviated or Unclear
```swift
struct PI: Codable
struct NM: Codable
class MKM: MobileKeyManager
class UKSM
```

## Code Organization

### File Structure

#### ✅ GOOD - Logical Grouping
```swift
// MARK: - Core Properties
private let handle: UnsafeMutableRawPointer
private let logger: Logger

// MARK: - Initialization
init(handle: UnsafeMutableRawPointer, logger: Logger) {
    self.handle = handle
    self.logger = logger
}

// MARK: - Public Interface
func initializeUserRootKey() throws { ... }
func getUserPublicKey() throws -> Data { ... }

// MARK: - Private Helpers
private func prepareProfileKeys(_ profileKeys: [Data]?) throws -> ([UnsafePointer<UInt8>?], [Int]) { ... }
```

#### ❌ BAD - Mixed Concerns
```swift
// Don't mix public and private methods randomly
func initializeUserRootKey() throws { ... }
private func helper() { ... }
func getUserPublicKey() throws -> Data { ... }
private func anotherHelper() { ... }
```

### Function Length

#### ✅ GOOD - Short, Focused Functions
```swift
// Main function orchestrates the flow
func encryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
    let (profileKeysArray, profileLensArray) = try prepareProfileKeys(profileKeys)
    
    var out: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let result = try performEnvelopeEncryption(
        data: data,
        networkId: networkId,
        profileKeysArray: profileKeysArray,
        profileLensArray: profileLensArray,
        out: &out,
        outLen: &outLen
    )
    
    return try processEncryptionResult(result: result, out: out, outLen: outLen)
}

// Helper functions handle specific tasks
private func prepareProfileKeys(_ profileKeys: [Data]?) throws -> ([UnsafePointer<UInt8>?], [Int]) {
    // Implementation details...
}

private func performEnvelopeEncryption(/* parameters */) throws -> Int32 {
    // Implementation details...
}
```

#### ❌ BAD - Long, Complex Functions
```swift
// Don't create monolithic functions
func encryptWithEnvelope(data: Data, networkId: String?, profileKeys: [Data]?) throws -> Data {
    // 50+ lines of mixed logic
    // Profile key preparation
    // Encryption logic
    // Error handling
    // Result processing
    // Memory management
}
```

## Memory Management

### FFI Memory Handling

#### ✅ GOOD - Proper Memory Management
```swift
func getUserPublicKey() throws -> Data {
    var out: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (_, err) = withRnError { errPtr in
        rn_keys_mobile_get_user_public_key(handle, &out, &outLen, errPtr)
    }
    
    if let error = err { throw error }
    
    guard let outPtr = out else { return Data() }
    let data = Data(bytes: outPtr, count: outLen)
    rn_free(outPtr, outLen)  // Always free FFI-allocated memory
    return data
}
```

#### ❌ BAD - Memory Leaks
```swift
func getUserPublicKey() throws -> Data {
    var out: UnsafeMutablePointer<UInt8>?
    var outLen = 0
    
    let (_, err) = withRnError { errPtr in
        rn_keys_mobile_get_user_public_key(handle, &out, &outLen, errPtr)
    }
    
    if let error = err { throw error }
    
    guard let outPtr = out else { return Data() }
    let data = Data(bytes: outPtr, count: outLen)
    // Missing rn_free(outPtr, outLen) - MEMORY LEAK!
    return data
}
```

### Defer Statements

#### ✅ GOOD - Using Defer for Cleanup
```swift
func generateNetworkDataKey() throws -> String {
    var out: UnsafeMutablePointer<CChar>?
    var outLen = 0
    
    let (_, err) = withRnError { errPtr in
        rn_keys_mobile_generate_network_data_key(handle, &out, &outLen, errPtr)
    }
    
    if let error = err { throw error }
    
    defer { 
        if let outString = out { 
            rn_string_free(outString) 
        } 
    }
    
    return out.map { String(cString: $0) } ?? ""
}
```

## Error Handling

### Consistent Error Patterns

#### ✅ GOOD - Consistent Error Handling
```swift
// Always use the same pattern for FFI errors
let (_, err) = withRnError { errPtr in
    rn_keys_mobile_initialize_user_root_key(handle, errPtr)
}

if let error = err { throw error }
```

#### ❌ BAD - Inconsistent Error Handling
```swift
// Don't mix different error handling patterns
let (_, err) = withRnError { errPtr in
    rn_keys_mobile_initialize_user_root_key(handle, errPtr)
}

if let e = err { throw e }  // Single letter variable
// ... later in the same file ...
if let error = err { throw error }  // Descriptive variable
```

## Testing Best Practices

### Test Organization

#### ✅ GOOD - Well-Organized Tests
```swift
func testCompleteFFIKeyManagementLifecycle() throws {
    print("🚀 Starting Complete FFI Key Management Lifecycle Test")
    
    // Phase 1: Mobile Setup
    let (mobileKeys, userPublicKey) = try setupMobileSide()
    
    // Phase 2: Node Setup
    let (nodeKeys, setupToken, encryptedSetupToken) = try setupNodeSide(userPublicKey: userPublicKey)
    
    // Phase 3: Certificate Exchange
    try performCertificateExchange(mobileKeys: mobileKeys, nodeKeys: nodeKeys, encryptedSetupToken: encryptedSetupToken)
    
    // Phase 4: Network Setup
    try performNetworkSetup(mobileKeys: mobileKeys, nodeKeys: nodeKeys)
}

// MARK: - Helper Methods
private func setupMobileSide() throws -> (KeysFFI, Data) {
    // Implementation details...
}

private func setupNodeSide(userPublicKey: Data) throws -> (KeysFFI, Data, String) {
    // Implementation details...
}
```

#### ❌ BAD - Monolithic Tests
```swift
func testCompleteFFIKeyManagementLifecycle() throws {
    // 100+ lines of mixed test logic
    // Setup, execution, validation all mixed together
    // Hard to understand what's being tested
    // Difficult to debug when failures occur
}
```

### Test Data

#### ✅ GOOD - Descriptive Test Data
```swift
let testData = Data("This is a test message that should be encrypted and decrypted".utf8)
let personalProfileKey = try mobileKeys.mobileDeriveUserProfileKey("personal")
let workProfileKey = try mobileKeys.mobileDeriveUserProfileKey("work")
```

#### ❌ BAD - Unclear Test Data
```swift
let data = Data("test".utf8)
let pk1 = try mobileKeys.mobileDeriveUserProfileKey("p")
let pk2 = try mobileKeys.mobileDeriveUserProfileKey("w")
```

## Common Anti-Patterns to Avoid

### 1. Single-Letter Variables
```swift
// ❌ BAD
let p = out
let e = err
let h = handle

// ✅ GOOD
let outPtr = out
let error = err
let handle = handle
```

### 2. Abbreviated Names
```swift
// ❌ BAD
let pk = publicKey
let ca = certificateAuthority
let nid = networkId

// ✅ GOOD
let publicKey = publicKey
let certificateAuthority = certificateAuthority
let networkId = networkId
```

### 3. Long Functions
```swift
// ❌ BAD - Function with 50+ lines
func doEverything() throws -> Data {
    // 50+ lines of mixed logic
}

// ✅ GOOD - Break into smaller functions
func doEverything() throws -> Data {
    let step1 = try performStep1()
    let step2 = try performStep2(step1)
    return try performStep3(step2)
}
```

### 4. Inconsistent Naming
```swift
// ❌ BAD - Mixed naming styles
let userPublicKey = try keys.getUserPublicKey()
let pk = try keys.getAgreementPublicKey()
let publicKey = try keys.getNodePublicKey()

// ✅ GOOD - Consistent naming
let userPublicKey = try keys.getUserPublicKey()
let agreementPublicKey = try keys.getAgreementPublicKey()
let nodePublicKey = try keys.getNodePublicKey()
```

## Performance Considerations

### Memory Allocation
- Use `withUnsafeBytes` for temporary memory access
- Always free FFI-allocated memory with appropriate free functions
- Use `defer` for cleanup to ensure it happens even if errors occur

### String Operations
- Use `withCString` for C string conversions
- Avoid unnecessary string allocations in tight loops

## Documentation

### Code Comments
```swift
/// Complete FFI Key Management Lifecycle Test
///
/// This test implements the EXACT same end-to-end cryptographic flow as ffi_lifecycle_test.rs
/// using the Swift FFI API. Every single step from the reference test is implemented here.
final class SwiftFFILifecycleE2ETest: XCTestCase {
    // Implementation...
}
```

### Function Documentation
```swift
/// Initialize the key store (platform-appropriate type)
/// 
/// - Throws: `KeyStoreError.unsupportedPlatform` if platform is not supported
/// - Note: iOS automatically uses mobile key store, macOS uses node key store
public func initialize() throws {
    // Implementation...
}
```

## Code Review Checklist

Before submitting code for review, ensure:

- [ ] All SwiftLint violations are resolved
- [ ] Code follows naming conventions
- [ ] Functions are appropriately sized (< 50 lines)
- [ ] Memory is properly managed
- [ ] Error handling is consistent
- [ ] Tests are well-organized and descriptive
- [ ] No single-letter variables exist
- [ ] No abbreviated names are used
- [ ] Code is properly documented

## Continuous Improvement

- Run `swiftlint lint Sources/` before each commit
- Use `swiftformat Sources/` to maintain consistent formatting
- Review and update this document as new patterns emerge
- Share learnings with the team to improve overall code quality

## Progress Tracking

### Linting Violations Reduction
- **Initial**: 119 violations (2 serious)
- **Current**: 6 violations (0 serious)
- **Reduction**: 95% improvement, 100% serious violations eliminated

### Violations Fixed
✅ **Function Parameter Count**: Used parameter structs to group related parameters
✅ **Large Tuple**: Replaced tuples with 3+ members with custom structs  
✅ **Function Body Length**: Extracted helper functions to reduce complexity
✅ **Line Length**: Broke long lines into multiple lines
✅ **Trailing Whitespace**: Removed all trailing whitespace
✅ **Identifier Names**: Replaced single-letter variables with descriptive names

### Remaining Violations
🔴 **Type Body Length**: Classes exceeding 250/350 line limits
🔴 **File Length**: Files exceeding 400 line limits  
🔴 **Function Body Length**: Functions exceeding 50 line limits
🔴 **Cyclomatic Complexity**: Functions with complexity > 10

### Lessons Learned
⚠️ **Helper Structs**: Adding helper structs to reduce function complexity can actually increase type body length
⚠️ **Trade-offs**: Sometimes fixing one violation introduces another - need to balance approaches
✅ **Parameter Structs**: Using parameter structs for functions with many parameters is effective
✅ **Function Extraction**: Breaking long functions into smaller ones is effective
✅ **Line Breaking**: Breaking long lines and function signatures is effective

## Linting Violation Fixes

### 1. Function Parameter Count Violations
```swift
// ❌ BAD - Too many parameters
func performEnvelopeEncryption(
    data: Data,
    networkId: String?,
    profileBuffers: ProfileKeyBuffers,
    profilePublicKeys: [Data],
    outCbor: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
    outLen: UnsafeMutablePointer<Int>
) -> (Int32, FFIError?)

// ✅ GOOD - Use parameter structs
struct EnvelopeEncryptionParams {
    let data: Data
    let networkId: String?
    let profileBuffers: ProfileKeyBuffers
    let profilePublicKeys: [Data]
    let outCbor: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
    let outLen: UnsafeMutablePointer<Int>
}

func performEnvelopeEncryption(_ params: EnvelopeEncryptionParams) -> (Int32, FFIError?)
```

### 2. Large Tuple Violations
```swift
// ❌ BAD - Tuple with more than 2 members
func prepareProfileKeyBuffers(_ profilePublicKeys: [Data]) -> (
    buffers: [UnsafeMutablePointer<UInt8>],
    pointers: [UnsafePointer<UInt8>?],
    lengths: [Int]
)

// ✅ GOOD - Use structs instead of tuples
struct ProfileKeyBuffers {
    let buffers: [UnsafeMutablePointer<UInt8>]
    let pointers: [UnsafePointer<UInt8>?]
    let lengths: [Int]
}

func prepareProfileKeyBuffers(_ profilePublicKeys: [Data]) -> ProfileKeyBuffers
```

### 3. Function Body Length Violations
```swift
// ❌ BAD - Function with 50+ lines
func encryptWithEnvelopeCBOR(...) throws -> Data {
    // 50+ lines of complex logic
}

// ✅ GOOD - Extract helper functions
func encryptWithEnvelopeCBOR(...) throws -> Data {
    let profileBuffers = prepareProfileKeyBuffers(profilePublicKeys)
    let (_, err) = performEnvelopeEncryption(...)
    // Cleanup and return
}

private func performEnvelopeEncryption(_ params: EnvelopeEncryptionParams) -> (Int32, FFIError?) {
    // Complex FFI logic extracted here
}
```

### 4. Trailing Whitespace
```bash
# Remove all trailing whitespace from Swift files
find Sources/ -name "*.swift" -exec sed -i '' 's/[[:space:]]*$//' {} \;
```

### 5. Line Length Violations
```swift
// ❌ BAD - Long line
if case let .unsignedInt(unsignedValue) = element, unsignedValue <= UInt64(UInt8.max) { out.append(UInt8(unsignedValue)) }

// ✅ GOOD - Break into multiple lines
if case let .unsignedInt(unsignedValue) = element,
   unsignedValue <= UInt64(UInt8.max) {
    out.append(UInt8(unsignedValue))
}
```

## Conclusion

Following these best practices will result in:
- **Maintainable code** that's easy to understand and modify
- **Consistent codebase** that follows established patterns
- **Fewer bugs** through better error handling and memory management
- **Easier testing** with well-organized test structures
- **Better collaboration** through clear naming and documentation

Remember: **Code is read much more often than it is written**. Write for the reader, not just for the compiler.

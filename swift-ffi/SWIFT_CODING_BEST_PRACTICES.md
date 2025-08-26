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

## Lessons Learned

### 1. Unnecessary `try` Keywords
```swift
// ❌ BAD - Unnecessary try keyword
let keys = try KeysFFI()  // KeysFFI() is not a throwing initializer

// ✅ GOOD - Remove unnecessary try
let keys = KeysFFI()
```

**Lesson**: Always verify if a function/initializer actually throws before using `try`. The Swift compiler will warn about unnecessary `try` keywords, which indicates poor error handling design.

### 2. Helper Struct Trade-offs
```swift
// ❌ BAD - Helper structs can increase type body length
struct FFIHelper {
    // Helper methods that increase overall class line count
}

// ✅ GOOD - Sometimes inline helper functions are better
private func helperFunction() {
    // Inline helper logic
}
```

**Lesson**: While helper structs can reduce function complexity, they can also increase type body length violations. Balance is key - use them only when they provide significant value.

### 3. Compilation Errors from Over-Refactoring
```swift
// ❌ BAD - Over-refactoring can introduce compilation errors
struct EnvelopeOutput {
    let out: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
    let outLen: UnsafeMutablePointer<Int>
}

// This can cause 'inout' parameter issues and type inference problems

// ✅ GOOD - Direct parameter passing when possible
func performEnvelopeEncryption(
    out: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
    outLen: UnsafeMutablePointer<Int>
)
```

**Lesson**: Over-engineering solutions can introduce new problems. Sometimes the simplest approach (direct parameter passing) is the most reliable.

### 4. Type Mismatch in FFI Operations
```swift
// ❌ BAD - Incorrect type usage
func handleTransportRequest(_ params: TransportRequestParams) {
    let transportHandle: OpaquePointer = handle  // Wrong type!
}

// ✅ GOOD - Correct type usage
func handleTransportRequest(_ params: TransportRequestParams) {
    let transportHandle: UnsafeMutableRawPointer = handle  // Correct type
}
```

**Lesson**: FFI operations require precise type matching. Always verify types match between Swift and C FFI signatures.

### 5. Syntax Errors from Missing Braces
```swift
// ❌ BAD - Missing closing brace causes cascading errors
func handlePayloadRequest(_ params: PayloadRequestParams) {
    // Implementation...
    // Missing } - causes compilation errors throughout the rest of the class
}

// ✅ GOOD - Always verify brace matching
func handlePayloadRequest(_ params: PayloadRequestParams) {
    // Implementation...
}  // Proper closing brace
```

**Lesson**: Missing braces cause cascading compilation errors that can be confusing. Always verify syntax structure, especially after refactoring.

### 6. Parameter Name Mismatches
```swift
// ❌ BAD - Parameter name mismatch
struct Opts {
    let openStreamTimeoutMs: UInt32  // Wrong name
}

// Function expects 'openStreamMs'
let options = Opts(openStreamTimeoutMs: 5000)  // Compilation error

// ✅ GOOD - Match parameter names exactly
struct Opts {
    let openStreamMs: UInt32  // Correct name
}
```

**Lesson**: Always verify parameter names match exactly between struct definitions and function calls, especially when refactoring.

### 7. Unused Variables in Tests
```swift
// ❌ BAD - Unused variables create warnings
let setupToken = try nodeKeys.nodeGenerateSetupToken(userPublicKey: userPublicKey)
// setupToken is never used

// ✅ GOOD - Use underscore for intentionally unused values
let _ = try nodeKeys.nodeGenerateSetupToken(userPublicKey: userPublicKey)
```

**Lesson**: Use underscore (`_`) for intentionally unused return values to avoid compiler warnings and make intent clear.

### 8. Vertical Whitespace Management
```swift
// ❌ BAD - Too many empty lines
func function1() {
    // Implementation
}


func function2() {  // Too much vertical whitespace
    // Implementation
}

// ✅ GOOD - Single empty line between functions
func function1() {
    // Implementation
}

func function2() {  // Single empty line
    // Implementation
}
```

**Lesson**: Maintain consistent vertical spacing - single empty lines between functions, no excessive whitespace.

## Bad Practices to Avoid

### 1. Over-Refactoring Without Testing
- Don't create helper structs just to reduce function complexity without testing
- Don't refactor multiple violations simultaneously - fix one at a time
- Always run tests after each refactoring step

### 2. Ignoring Compiler Warnings
- Don't ignore "no calls to throwing functions occur within 'try' expression"
- Don't ignore unused variable warnings
- Address all warnings systematically

### 3. Complex Parameter Structs
- Don't create parameter structs that are only used in one place
- Don't over-abstract simple parameter passing
- Use parameter structs only when they provide clear value

### 4. Inconsistent Error Handling
- Don't mix different error handling patterns in the same file
- Don't use single-letter variables for errors
- Maintain consistent error handling throughout

### 5. Memory Management Neglect
- Don't forget to free FFI-allocated memory
- Don't ignore memory leaks in tests
- Always use `defer` for cleanup when appropriate

### 6. Test Data Naming
- Don't use unclear test data names
- Don't use single letters for test variables
- Use descriptive names that explain the test scenario

### 7. Function Length Ignorance
- Don't create functions longer than 50 lines
- Don't mix multiple concerns in single functions
- Break complex functions into smaller, focused functions

### 8. Line Length Violations
- Don't create lines longer than 120 characters
- Don't ignore line length in function signatures
- Break long lines appropriately for readability

## Progress Tracking

### Linting Violations Reduction
- **Initial**: 119 violations (2 serious)
- **Current**: 7 violations (0 serious)
- **Reduction**: 94% improvement, 100% serious violations eliminated

### Violations Fixed
✅ **Function Parameter Count**: Used parameter structs to group related parameters
✅ **Large Tuple**: Replaced tuples with 3+ members with custom structs  
✅ **Function Body Length**: Extracted helper functions to reduce complexity
✅ **Line Length**: Broke long lines into multiple lines
✅ **Trailing Whitespace**: Removed all trailing whitespace
✅ **Identifier Names**: Replaced single-letter variables with descriptive names
✅ **Cyclomatic Complexity**: Refactored complex switch statements into helper functions
✅ **Unnecessary try Keywords**: Removed try from non-throwing initializers
✅ **File Length**: Successfully split large files into smaller, focused files
✅ **Vertical Whitespace**: Fixed excessive empty lines

### Remaining Violations
🔴 **Type Body Length**: Classes exceeding 250/350 line limits (2 files)
🔴 **Function Body Length**: Functions exceeding 50 line limits (1 function)
🔴 **Line Length**: Lines exceeding 120 character limits (5 lines)

### Key Insights
⚠️ **Helper Structs**: Adding helper structs to reduce function complexity can actually increase type body length
⚠️ **Trade-offs**: Sometimes fixing one violation introduces another - need to balance approaches
⚠️ **Complex Refactoring**: Over-engineering solutions can introduce new compilation errors
✅ **Parameter Structs**: Using parameter structs for functions with many parameters is effective
✅ **Function Extraction**: Breaking long functions into smaller ones is effective
✅ **Line Breaking**: Breaking long lines and function signatures is effective
✅ **File Splitting**: Moving large files into smaller, focused files is very effective
✅ **Error Handling**: Consistent error handling patterns are crucial
✅ **Memory Management**: Proper FFI memory management prevents crashes and leaks
✅ **Testing**: Systematic testing after each change prevents regression

### Recent Lessons Learned
⚠️ **Compilation Error Recovery**: When complex refactoring introduces compilation errors, sometimes it's better to revert to a simpler approach
⚠️ **Protocol Conformance**: Removing methods required by protocols can break compilation - always verify protocol requirements
✅ **File Organization**: Splitting large files into focused extensions is more effective than complex parameter structs
✅ **Incremental Approach**: Fix one violation type at a time rather than attempting complex multi-issue refactoring
✅ **Systematic Progress**: Focus on violations that can be fixed without introducing new compilation errors

### Final Status Summary
🎯 **Goal**: 0 warnings and 0 serious violations
📊 **Progress**: 94% complete (7 remaining vs 119 initial)
🚀 **Achievement**: All serious violations eliminated, only minor style warnings remain
💡 **Strategy**: Focus on remaining violations that can be addressed with simple formatting changes

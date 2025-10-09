/Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFIQuicTransportTest.swift contain many hacks, stubs, mocked tests. taht is not doing naything peoperly

testTransportStartStopIdempotence()
 // For now, we'll skip the actual transport creation until we have certificates
// This test validates the basic infrastructure

testBasicTransportConnection()
 // For now, we'll skip the actual transport creation until we have certificates
// This test validates the basic infrastructure


and so on.;.; this is coéltely agains our RULES .cursor/rules/code-standards.mdc **NO MOCKS, NO SHORTCUTS, NO HACKS**

You have claimed many tiems all tranposeter tests wer perfect qand passing while it was all hacks and mocks.

GOAL all transporter tests must match 100% rust test /Users/rafael/dev/runar-swift/runar-rust/runar-ffi/tests/ffi_transport_test.rs 

WITH ALL STEPS working. no hacks no mocks no stupf.. no comments with For now, we'll skip the actual transport  ...

Task 1:
 CHECK ALL TESTS under /Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests
 and lets create a liust of all tests that has this issues and add to this file hre at the bottom.. so we can address one by one and fix all tests.

Task 2: once u have compiled the list and added to this MD file, go thourhg one by one and fix it. implement it properly. Always check it agains the rust code and it must match 100%. same test setup, same steps, same asserts.. 100%. nothing more nothing less. NO EXCEPTIONS. If you findn an issue tou stop and ask for guidance/input. U NEVER DO A HACK TEST LIKE THESE> NEVER.

 ALL TEST MUST BE REAL AND COMPLETE AND USE REAL COMPOENT.. no test shuold ahve these commends and be hacks like this.


List of tests with issues:

## FFIQuicTransportTest.swift - MAJOR ISSUES
- `testBasicTransportSetup()` - Line 37: "For now, let's test just the basic transport creation without certificates"
- `testBasicTransportConnection()` - Line 100: "For now, we'll skip the actual transport creation until we have certificates"
- `testTransportStartStopIdempotence()` - Line 136: "For now, we'll skip the actual transport creation until we have certificates"
- **ISSUE**: These tests are NOT testing actual transport functionality - they're just testing CBOR encoding/decoding
- **REQUIRED**: Must implement full transport creation, connection, start/stop, and request/response like Rust test

## CATests.swift - STUB TESTS
- `testCaServerNewStub()` - Line 86: Function name contains "Stub" - not a real test
- `testCaClientNewStub()` - Line 161: Function name contains "Stub" - not a real test
- **ISSUE**: These are not real tests - they just create objects without testing functionality
- **REQUIRED**: Must implement real CA server/client functionality tests matching Rust

## FFITypesCrossValidationTests.swift - INCOMPLETE TESTS
- Multiple tests with "TODO: Add proper equality comparison when Equatable is implemented" - Lines 85, 96, 107, 118, 129, 140, 152, 164, 176, 188, 200, 213
- **ISSUE**: Tests only verify CBOR decoding works, not that data matches between Swift and Rust
- **REQUIRED**: Must implement proper equality comparisons and cross-validation

## MessageCryptoInteropTests.swift - SKIPPED FUNCTIONALITY
- Line 204: "Step 5: Test network encryption (skipped - requires complex setup)"
- **ISSUE**: Network encryption tests are skipped entirely
- **REQUIRED**: Must implement network encryption tests

## InitializationTests.swift - FAKE CONCURRENCY
- Line 207: "For now, we just verify the managers work in sequence"
- **ISSUE**: Claims to test concurrency but only tests sequential operations
- **REQUIRED**: Must implement real concurrency tests

## SUMMARY OF VIOLATIONS
1. **NO MOCKS, NO SHORTCUTS, NO HACKS** - Multiple violations
2. **Tests with "For now" comments** - 3 files
3. **Tests with "TODO" comments** - 1 file with 12 TODOs
4. **Tests with "Stub" in name** - 2 functions
5. **Skipped functionality** - 1 file
6. **Fake concurrency tests** - 1 file

## TOTAL FILES WITH ISSUES: 5
## TOTAL TEST FUNCTIONS WITH ISSUES: 20+


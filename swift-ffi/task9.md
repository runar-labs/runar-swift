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


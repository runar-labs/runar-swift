you claimed the serializer tests was using proper real ecryption using our FFI package key managers, but I found this in the tests the use of TestKeyManagerAdapter which is a mock/stub agains our rules @code-standards.mdc NO MOCKS, NO SHORTCUTS, NO HACKS .. @TestKeyManagerAdapter.swift thisis a hack/stub..;. /Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFIKeysE2ETest.swift this test shows how to use the proper FFI Key managers to encrypt and decrypt data and how to setup the key manager. 

GOAL is t o fix ALL all tests in the @swift-serializer/ and @swift-serializer-macros/ packages and remove all mocks, hacks, stubs and shortcuts like TestKeyManagerAdapter and replace with real components.

ALKL OUR TEST MUST USE REAL COMPONENTS no mocks allowed anywhere.
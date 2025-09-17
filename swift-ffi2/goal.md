FFIE2EIntegrationTest_baseline is ourt baselined test DO NORT CHANGE IT UNDER ANY CISRCUSTANCE

This test shows the use of the FFI firectly.. and how that it is working as epecged.. this test matched the rust test /Users/rafael/dev/runar-swift/runar-rust/runar-ffi/tests/ffi_e2e_integration_test.rs

THE GOAL IS TO create a Swift FFI Wrapper LIBRARY that uses the Rust FFI (like this test does) but exposes a Swift API.. to avoid having to use the FFI firectly like the test  FFIE2EIntegrationTest_baseline does..


We also need a test taht does all the same 10 phases.. same steps.. same setup same asserts, but using the Swift FFI Wrapper LIBRARY .. to validate taht the LIbrary works as epected.. we alreaduy have on go,l but got stuck in a issue that we could not solve. so we decided to start from scratch.

The LIbrary test shold not use any FFI directly, like the FFIE2EIntegrationTest_baseline  . it shuold only use the Swift FFI Wrapper LIBRARY API and Types. BUT as I said it shiould be 100% aligned to the FFIE2EIntegrationTest_baseline  and ahve all the same phases and same setup and scenarions and asserts.

Every time you run a test, save the log to a file and analise the logs LINE BY LINE. no grep, no find which always lead to false positives. ALWAYS analise the code and logs LINE BY LINE in details througuly and systematicaly.

A COMMON IMSTAKE U MADE repeately is that on phase 4 there is a review step which should succed. but in phase 10 the review shoulf fail (It is a negative test and it expects it to fail)

The types (CBOR serialized types defined in the /Users/rafael/dev/runar-swift/swift-ffi  have been validated agains rust.. so u shouold copy them to acoid creating new one with issue.. but everythig  else. u shold implement from scratch based onw hat u see in the FFIE2EIntegrationTest_baseline and how it works. DO NOT COPY ANYTHING ELSE FROM THRE since that impl has issues we could not solve.. start from scratch

AD DETAILED LOGS TO THE Seift FFI LIbrary code.. so we can debut what is happening. add proper Info, debug and trace logs. Use our logger /Users/rafael/dev/runar-swift/swift-common/Sources/SwiftCommon/Logger.swift  DO NOT USE Print() anywhere use our logger proper and follow oru logging guidelines.

NO Hacks, no shortcuts, no mocks, no stubs. ALWAYS Follow Swift and FFI best practices.
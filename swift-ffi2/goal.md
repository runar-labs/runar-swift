Must dos:
FFIE2EIntegrationTest_baseline is our baselined test DO NOT CHANGE IT UNDER ANY CISRCUSTANCE and do not break it.

IT uses some APIS that u will likely want to change, when doing it so keep the verstion that this tests uses.. to the test continues and mark them as deprecated so at the end with the LIB and new tests all works perfectaly we can re3move teh baseline test and any APIs it uses that is deorecated.

This test shows the use of the FFI firectly.. and how that it is working as expected.. this test matches the rust reference test /Users/rafael/dev/runar-swift/runar-rust/runar-ffi/tests/ffi_e2e_integration_test.rs

Goals
Your #1 GOAL IS TO create a Swift FFI Wrapper LIBRARY that uses the Rust FFI (like this test does) but exposes a nice Swift API, followig seift best practices, naming conventions and best practices. To avoid having to use the FFI firectly like the test  FFIE2EIntegrationTest_baseline does.


Your Goal #2 is to craete a test that does all the same 10 phases, same steps, same setup same asserts as the FFIE2EIntegrationTest_baseline and ffi_e2e_integration_test.rs, BUT using the Swift FFI Wrapper LIBRARY. to validate the LIbrary works as epected and how how it works end to end. we alreaduy have on go at this (/Users/rafael/dev/runar-swift/swift-ffi) ,but got stuck in an segfault issue that we could not solve. so we decided to start from scratch. in this folder /Users/rafael/dev/runar-swift/swift-ffi2

The new LIbrary test shold not use any FFI directly, like the FFIE2EIntegrationTest_baseline  . it shuold only use the Swift FFI Wrapper LIBRARY API and Types. BUT as I said it shiould be 100% aligned to the FFIE2EIntegrationTest_baseline  and ahve all the same phases and same setup and scenarions and asserts.

Strategy/Lessons learned
Every time you run a test, save the log to a file and analise the logs LINE BY LINE. no grep, no find which always lead to false positives. ALWAYS analise the code and logs LINE BY LINE in details in its entirety and systematicaly.

A COMMON IMSTAKE WE MADE repeately is that on phase 4 there is a review step which should succed. but in phase 10 the review shoulf fail (It is a negative test and it expects it to fail)

The types (CBOR serialized types defined in the /Users/rafael/dev/runar-swift/swift-ffi  have been validated against rust.. so u can copy them to avoid creating new ones with issues. but everythig  else. u shold implement from scratch based on what u see in the FFIE2EIntegrationTest_baseline and how it works. DO NOT COPY ANYTHING ELSE FROM THRE since that impl has issues we could not solve.. start from scratch

ADD DETAILED LOGS TO THE Swift FFI LIbrary code.. so we can debug what is happening. add proper Info, debug and trace logs. Use our logger /Users/rafael/dev/runar-swift/swift-common/Sources/SwiftCommon/Logger.swift  DO NOT USE Print() anywhere use our logger proper and follow our logging guidelines.

NO Hacks, no shortcuts, no mocks, no stubs. ALWAYS Follow Swift and FFI best practices.
GOAL
Continue to implement the swift FFI Wrapper library

Goal #0 - as part of the first task I did not asee an Swift wrapper for the FFI logger API.. where we can set the loglevel  and set nodeid/context in the Rust logger.. this is needed and shuold bhe used in oru tests.. so we can see details logs in the rust side also.

Goal #1 implement all the FFI APIS of the rust crate runar-keys - we already implemented some of this as part of ttask1as1, so avoid duplciation, this is a continuation.

Goal #2 To validate the keys functoinality (via FFI) we need a test in Swift using the Lirabry that mirrors the rust test /Users/rafael/dev/runar-swift/runar-rust/runar-keys/tests/end_to_end_test.rs and /Users/rafael/dev/runar-swift/runar-rust/runar-keys/tests/primitives_e2e_test.rs

Goal #3 implement all the FFI APIS of the rust crate runar-transporter - we already implemented some of this as part of task1, so avoid duplciation, this is a continuation.

Goal #4 To validate the transporter functionality (over FFI) we need a test in Swift using the Lirabry that mirrors the rust test /Users/rafael/dev/runar-swift/runar-rust/runar-node-tests/src/network/quic_transport_test.rs

Specialy the scenario:
test_quic_transport (Lines 216-640) - MAIN COMPREHENSIVE TEST
Scenario: Full bidirectional communication with all message types
Setup: Two complete QUIC transport instances with full certificate infrastructure
Message Types Tested:
✅ Request/Response: Bidirectional request-response patterns
✅ Events: Unidirectional event publishing
✅ Handshakes: Connection establishment
✅ Discovery: Peer connection and identification
Features Tested:
Certificate-based mTLS security
Message routing and callbacks
Connection lifecycle management
Message size limits (1024 bytes max)
Error handling for oversized messages

The other sceanrions, if possible (if we have FFI APIS for it) we shuold also implement in swift to make sure  all works over the FFI as expected and as it works in the Rust side.

Overal goal is to have a swift ffi wrapper liabrary with all the functionality that is available in /Users/rafael/dev/runar-swift/runar-rust/runar-ffi and test it properly with proper e2e tsts taht validates and show the whole functionality.
Context:
/Users/rafael/dev/runar-swift/swift-node is the swift version of /Users/rafael/dev/runar-swift/runar-rust/runar-node the main P2P node component where services are registered and can be interact with each other over the p2p network.

In the rust version the network is managed by the /Users/rafael/dev/runar-swift/runar-rust/runar-transporter which in swift we access over the FFI interface /Users/rafael/dev/runar-swift/swift-ffi and the QuicTransport type.
example of how it works here /Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFIQuicTransportTest.swift

In the rust version the Key Managers are directly managed form the /Users/rafael/dev/runar-swift/runar-rust/runar-keys craete. in swift we also use the /swift-ffi package.. which provides the NodeKeyManager and MobileKeyManager


The P2P node is responsible to based on config. decide which one to use, MobileKeyManager or NodeKeyManager and then passing it to the downstream components (transporter and serializer /Users/rafael/dev/runar-swift/swift-serializer)


GOAL implement PHASE 1: Core Node Structure (Local-First) from the plan.md

Go step by step. follow our rules /Users/rafael/dev/runar-swift/.cursor/rules/code-standards.mdc

Method:
1) Stick to the plan and our rules at all times.

2) No Guess, for every features read the rust code, in detail, line by line, no assumptoins, no greps.. read it in detail and line by line, methodicaly to build a complete understanding of the features. Find the tests for that featuture and read the tests also. So u have a complete view and understanding of how the feature works, all data flows, rules, API, edge cases and the actual use of it from the tests.
Build a complete understanding from first principles before u code in swift.

3) code de feature following swift 6 best practices. No shortcure, no todos, no mocks, no hacks, NO SIMPLIFICATIONS. IF U GET STUCK, stop and ask for guidance. DO NO TRY TO SIMPLIFY THINGS> YOU MUST IMPLEMENT EVERY FETUARE EXACTLY LIKE WE HAVE IN RUST ALREADY. U HAVE A SOLID WORKING REFERENCE IN RUST

4) When testing a feature also check teh rust test and create the same rust tests in swift. 
Before create a test check for existing tests properly, avoid duplication and test proliferation.

5) review the code and test code agains rust again at the end of each feature. To make sure it aligns 100% - nothing more, nothing less. 

DO NOT USE @unchecked Sendable  ANYWHERE THIS IS PROHIBED IN OUR RULES

We have implemented /Users/rafael/dev/runar-swift/swift-common/Sources/SwiftCommon/ShardedConcurrentMap.swift as the equivalent of RUST DAshMap .. so anywhere the rust code uses DAshMap u must use our ShardedConcurrentMap.
Context:
/Users/rafael/dev/runar-swift/swift-node is the swift version of /Users/rafael/dev/runar-swift/runar-rust/runar-node the main P2P node component where services are registered and can be interact with each other over the p2p network.

In the rust version the network is managed by the /Users/rafael/dev/runar-swift/runar-rust/runar-transporter which in swift we access over the FFI interface /Users/rafael/dev/runar-swift/swift-ffi and the QuicTransport type.
example of how it works here /Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFIQuicTransportTest.swift

In the rust version the Key Managers are directly managed form the /Users/rafael/dev/runar-swift/runar-rust/runar-keys craete. in swift we also use the /swift-ffi package.. which provides the NodeKeyManager and MobileKeyManager


The P2P node is responsible to based on config. decide which one to use, MobileKeyManager or NodeKeyManager and then passing it to the downstream components (transporter and serializer /Users/rafael/dev/runar-swift/swift-serializer)

GOAL
Implement in Swift the same NodeConfig, Node lifecycle, start, stop, service apis add_service, same registries:
service_registry: Arc<ServiceRegistry>,
// Centralized peer directory (single source of truth)
// peer_directory: Arc<PeerDirectory>,
remote_node_info: Arc<DashMap<String, NodeInfo>>,
// Debounce repeated discovery events per peer
discovery_seen_times: Arc<DashMap<String, Instant>>, 

same event subscriptoin/management:
/// Retained event store: exact full topic -> deque of (timestamp, data)
/// Wrapped in Arc to ensure Node clones share the same storage
retained_events: Arc<RetainedEventsMap>,
/// Index of exact topics for wildcard lookups
retained_index: Arc<RwLock<PathTrie<String>>>,

and etc.

This is a starter list, but not complete. Once you get this done you need to review the rust code for more and make sure seift has all the same functoinality. the target is 100% alignemnt of swift and rust code. 

Method:
1) Do one feature at the time.

2) Before coding in seift check the rust code in details, no assunptoins no guesses. read the rust code line by line in details and methodicaly and systematicaly to build a complete understanding of the functnality before u code in swift. no guess work.

3) Implement the feature. 

4) Test the feature.

5) Review the seift code against the rust code to make sure everythig is properly aligned. same dataflow, same rules. same API same outcome. no exceptions


Testing:
The swift tests must also align with rust. all tests we have in rust we must also add ot the swift impl and the tests must be 100% aligned also. same setup. same steps.. same asserts.. 100% aligneg. nothing more nothing less. DO NOT GUESS OR SKIP ANYTHING> be methodical , detailed and systematic.

Run the seift test with trace logs and run teh rust test with trace logs (set logLevel to trace) and compare the log output to make sure both tests actualy do the same things that are supposed ot do.


Task 1:
Based on all these instructions read the existing code in /Users/rafael/dev/runar-swift/swift-node and check the rust code. and lets create a detailed plan bellow with all the steps you need to take. Things u need to remove from /Users/rafael/dev/runar-swift/swift-node, things tyou need to change, and things u need to add to achieve the goal. So we have a details plan with all the steps that we can then track teh progress against.


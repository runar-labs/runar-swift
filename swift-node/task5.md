Context:
/Users/rafael/dev/runar-swift/swift-node is the swift version of /Users/rafael/dev/runar-swift/runar-rust/runar-node the main P2P node component where services are registered and can be interact with each other over the p2p network.

In the rust version the network is managed by the /Users/rafael/dev/runar-swift/runar-rust/runar-transporter which in swift we access over the FFI interface /Users/rafael/dev/runar-swift/swift-ffi and the QuicTransport type.
example of how it works here /Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFIQuicTransportTest.swift

In the rust version the Key Managers are directly managed form the /Users/rafael/dev/runar-swift/runar-rust/runar-keys craete. in swift we also use the /swift-ffi package.. which provides the NodeKeyManager and MobileKeyManager


The P2P node is responsible to based on config. decide which one to use, MobileKeyManager or NodeKeyManager and then passing it to the downstream components (transporter and serializer /Users/rafael/dev/runar-swift/swift-serializer)


GOAL implement  PHASE 6 - Network Integration from the plan.md

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

if u find a problem with the /Users/rafael/dev/runar-swift/swift-serializer or /Users/rafael/dev/runar-swift/swift-common package.. stop and providfe me the details.. DO NOT CHANGE IT witout my approaval.



Review 01- issues:

### **1. Network Message Structure Mismatch**

**Rust Implementation:**
```rust
// Rust uses structured NetworkMessage
pub struct NetworkMessage {
    pub source_node_id: String,
    pub destination_node_id: String,
    pub message_type: u8,
    pub payload: NetworkMessagePayloadItem,
}

pub struct NetworkMessagePayloadItem {
    pub path: String,
    pub payload_bytes: Vec<u8>,
    pub correlation_id: String,
    pub profile_public_keys: Vec<Vec<u8>>,
    pub network_public_key: Option<Vec<u8>>,
}
```

**Swift Implementation:**
```swift
// Swift uses separate parameters - NO STRUCTURED MESSAGE
requestCallback: { requestId, path, payload, sourcePeerId, correlationId in
    return Data() // Just returns raw data - WRONG.. the Callback shuold return a prtoper NetworkMessage and the CBOR serialiszation to DATA should be done internaly in the FFI layer
}
```

### **2. CBOR Serialization/Deserialization Missing**

**Rust Implementation:**
```rust
// Rust properly deserializes network payload
let payload = ArcValue::deserialize(
    &msg.payload.payload_bytes,
    Some(Arc::new(NodeKeyManagerWrapper(self.keys_manager.clone()))),
)?;

// Rust properly serializes response
let serialized_data = response.serialize(Some(&serialization_context))?;
```

**Swift Implementation:**
```swift
// Swift uses placeholder - NO REAL SERIALIZATION
let deserializedPayload = AnyValue.null() // ← PLACEHOLDER!
let serializedResponse = Data() // ← PLACEHOLDER!
```

### **3. Encryption Context Missing**

**Rust Implementation:**
```rust
// Rust creates proper serialization context with encryption
let serialization_context = SerializationContext {
    keystore: Arc::new(NodeKeyManagerWrapper(self.keys_manager.clone())),
    resolver,
    network_public_key: network_public_key.clone(),
    profile_public_keys: profile_public_keys.clone(),
};
```

**Swift Implementation:**
```swift
// Swift has NO encryption context
// Missing: SerializationContext, keystore, resolver, network_public_key, profile_public_keys
```

### **4. Request/Response Correlation Missing**

**Rust Implementation:**
```rust
// Rust properly handles correlation IDs and creates response messages
Ok(NetworkMessage {
    source_node_id: self.node_id.clone(),
    destination_node_id: msg.source_node_id,
    message_type: MESSAGE_TYPE_RESPONSE,
    payload: NetworkMessagePayloadItem {
        path: msg.payload.path.clone(),
        payload_bytes: serialized_data,
        correlation_id: msg.payload.correlation_id.clone(),
        profile_public_keys,
        network_public_key: Some(network_public_key.clone()),
    },
})
```

**Swift Implementation:**
```swift
// Swift ignores correlation ID and returns empty data
let serializedResponse = Data() // ← NO CORRELATION, NO RESPONSE STRUCTURE
```

## **What This Means:**

1. **No Real Data Exchange**: The Swift implementation can't actually send or receive meaningful data
2. **No Encryption**: All data is sent in plain text (if it worked)
3. **No Request/Response Matching**: Responses can't be matched to requests
4. **No Error Handling**: Errors can't be properly serialized and sent back
5. **No Security**: No profile public keys, no network public keys, no encryption

## **The Result:**

When you try to make a network request in Swift:
- ✅ **Transport Layer**: QUIC connection works
- ❌ **Data Layer**: No real data can be sent/received
- ❌ **Security Layer**: No encryption/decryption
- ❌ **Protocol Layer**: No proper request/response handling

**This is why I said "Network Communication is Broken"** - the transport works, but the actual data exchange protocol is completely missing.

The Swift implementation needs to be rebuilt to match the Rust `NetworkMessage` structure and implement proper CBOR serialization with encryption context.
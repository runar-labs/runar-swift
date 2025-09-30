
GOAL fix this mismatch.. the requestCallback shuold return a proper NetworkMessage instance and the CBOR serialisation to DATA should be done internaly in the FFI layer.

FIX THIS and udpate the test /Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFIQuicTransportTest.swift to use this updated API. and fix any other test in the FFI pakcage that needs to aligfn with this enw API.. NO BACKWARDS compathy.. complete refactory.. keeo code clean and organized.

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


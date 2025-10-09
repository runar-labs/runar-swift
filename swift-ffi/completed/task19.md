GOAL 1 change RequestCallback and EventCallback to be async
AND

GOAL 2 remove public let getLocalNodeInfoCallback: GetLocalNodeInfoCallback? ..
getLocalNodeInfoCallback is a rust side only feaites and shoulow not exit in swift.. swift uses the update node info FFI method ot updat eh node ifo everythig it change.s. this callback is never used..

Goal 3 - update  Swift Request and Event Structures to include sourcePeerId and destination Id as per the latest RUST changes to addres this issue:

Changes Made
Updated Event Structures:
Added source_peer_id: String and destination_peer_id: String to TransportRequestEvent
Added source_peer_id: String and destination_peer_id: String to TransportEventEvent
Fixed FFI Callback Implementations:
Updated request callback to pass req.source_node_id and req.destination_node_id from NetworkMessage
Updated event callback to pass ev.source_node_id and ev.destination_node_id from NetworkMessage
Updated Tests:
Enhanced the transport test to validate that source and destination peer IDs are present and not empty
Added debug output to verify the correct peer IDs are being passed through



#### **1. FFI Layer (Synchronous)**
```swift
// Current Swift FFI definition - SYNCHRONOUS
public typealias RequestCallback = @Sendable (String, String, Data, String, String?) -> NetworkMessage
public typealias EventCallback = @Sendable (String, String, Data, String, String?) -> Void
```

#### **2. Rust Implementation (Asynchronous)**
```rust
// Rust callback definitions - ASYNCHRONOUS
pub type RequestCallback = Arc<dyn Fn(NetworkMessage) -> BoxFuture<'static, Result<NetworkMessage>> + Send + Sync>;
pub type EventCallback = Arc<dyn Fn(NetworkMessage) -> BoxFuture<'static, Result<()>> + Send + Sync>;
```

#### **3. Downstream Swift Components (Asynchronous)**
```swift
// SwiftNode action handlers - ASYNCHRONOUS
public typealias ActionHandler = @Sendable (AnyValue?, RequestContext) async throws -> AnyValue
public typealias EventHandler = @Sendable (AnyValue?) async -> Void
```

 **Downstream Expectation**: All downstream components (SwiftNode, services, handlers) are designed to be `async`


### **The Solution: Chantge Transporter Callbacks to be async

The `QuicTransport` wrapper already handles the sync bridge over FFI correctly with its polling mechanism. Here's what should happen:

#### **1. Change all callbacks to be async -  the polling method already dispatched a task to call the calbacjks.. they are already in a async context.
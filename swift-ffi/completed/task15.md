NodeInfo Should Be Transport-Scoped, Not Keys-Scoped

### The Architectural Problem

**Current (Incorrect) Design:**
- `rn_keys_set_local_node_info` - NodeInfo is stored in the **keys** object
- Multiple key manager instances = multiple NodeInfo storage locations
- Transport reads from keys-scoped shared holder
- When testing multiple transports, they all read from different keys instances

**Correct Design Should Be:**
- `rn_transport_set_local_node_info` - NodeInfo should be stored in the **transport** object
- Each transport has its own NodeInfo storage
- Transport reads from its own NodeInfo storage
- Multiple transports can have different NodeInfo independently

### Detailed Analysis of Current Implementation

#### 1. **Current FFI Function (WRONG)**
```rust
// runar-rust/runar-ffi/src/lib.rs:4393
pub unsafe extern "C" fn rn_keys_set_local_node_info(
    transport: *mut c_void,  // ← This is actually a transport handle, not keys!
    node_info_cbor: *const u8,
    len: usize,
    err: *mut RnError,
) -> i32 {
    // ...
    let handle = &mut *(transport as *mut FfiTransportHandle);  // ← Transport handle
    // ...
    inner_ref.local_node_info.store(Arc::new(Some(node_info.clone())));  // ← Keys storage
}
```

**Problem**: The function name says `rn_keys_` but it takes a **transport handle** and updates **keys storage**.

#### 2. **Current Swift Usage (WRONG)**
```swift
// swift-node/Sources/SwiftNode/SwiftNode.swift:2034
let keyManager: FFIKeys = try config.getKeyManager()
let nodeInfoCbor = try CodableCBOREncoder().encode(ffiNodeInfo)
try await keyManager.setLocalNodeInfo(nodeInfoCbor)  // ← Calls keys method
```

**Problem**: Swift calls `keyManager.setLocalNodeInfo()` but this should be `transport.setLocalNodeInfo()`.

#### 3. **Current Transport Creation (WRONG)**
```rust
// runar-rust/runar-ffi/src/lib.rs:3936-3948
let holder = keys_inner.local_node_info.clone();  // ← Reads from keys
let get_local_node_info_cb: GetLocalNodeInfoCallback = Arc::new(move || {
    let holder = holder.clone();
    Box::pin(async move {
        let cur = holder.load();  // ← Reads from keys storage
        // ...
    })
});
```

**Problem**: Transport callback reads from keys storage instead of transport storage.

### The Multi-Transport Testing Issue

When testing multiple transports (like in `RemoteNetworkTests`):

1. **Node1**: Creates `FFIKeys1` → Creates `Transport1` → `Transport1` reads from `FFIKeys1.local_node_info`
2. **Node2**: Creates `FFIKeys2` → Creates `Transport2` → `Transport2` reads from `FFIKeys2.local_node_info`
3. **Node1** calls `FFIKeys1.setLocalNodeInfo()` → Updates `FFIKeys1.local_node_info`
4. **Node2** calls `FFIKeys2.setLocalNodeInfo()` → Updates `FFIKeys2.local_node_info`
5. **Handshake**: `Transport1` reads from `FFIKeys1.local_node_info` (correct)
6. **Handshake**: `Transport2` reads from `FFIKeys2.local_node_info` (correct)

But the current implementation has the wrong function name and wrong storage location.

### Evidence from Code Analysis

#### 1. **Function Signature Mismatch**
```rust
// Function name suggests it's for keys
pub unsafe extern "C" fn rn_keys_set_local_node_info(
    transport: *mut c_void,  // But takes transport handle
    // ...
)
```

#### 2. **Swift FFI Method (WRONG)**
```swift
// swift-ffi/Sources/SwiftFFI/SwiftFFI.swift:3068
public func setLocalNodeInfo(_ nodeInfoCbor: Data) async throws {
    // This is on FFIKeys, but should be on QuicTransport
}
```

#### 3. **Transport Callback Reads Wrong Storage**
```rust
// runar-rust/runar-transporter/src/transport/quic_transport.rs:1230
let local_node_info = (self.get_local_node_info)()  // Reads from keys storage
    .await
    .map_err(|e| NetworkError::TransportError(e.to_string()))?;
```

### The Correct Architecture Should Be

#### 1. **Transport-Scoped NodeInfo Storage**
```rust
// In QuicTransport struct
pub struct QuicTransport {
    // ... existing fields ...
    local_node_info: Arc<AtomicRefCell<Option<NodeInfo>>>,  // ← Transport-scoped storage
}
```

#### 2. **Transport-Scoped FFI Function**
```rust
// Correct function name and scope
pub unsafe extern "C" fn rn_transport_set_local_node_info(
    transport: *mut c_void,
    node_info_cbor: *const u8,
    len: usize,
    err: *mut RnError,
) -> i32 {
    // Update transport.local_node_info, not keys.local_node_info
}
```

#### 3. **Transport-Scoped Swift Method**
```swift
// In QuicTransport class
public func setLocalNodeInfo(_ nodeInfoCbor: Data) async throws {
    // Call rn_transport_set_local_node_info
}
```

#### 4. **Transport-Scoped Callback**
```rust
// In transport creation
let local_node_info = self.local_node_info.clone();  // ← Transport storage
let get_local_node_info_cb: GetLocalNodeInfoCallback = Arc::new(move || {
    let holder = local_node_info.clone();  // ← Transport storage
    Box::pin(async move {
        let cur = holder.borrow();  // ← Read from transport storage
        // ...
    })
});
```

### Why This Fixes the Issue

1. **Isolation**: Each transport has its own NodeInfo storage
2. **Correct Scope**: NodeInfo belongs to transport, not keys
3. **Multi-Transport Support**: Multiple transports can have different NodeInfo
4. **Proper Lifecycle**: NodeInfo is updated when transport is updated, not when keys are updated

### Summary for FFI Fix

**Current Problem:**
- `rn_keys_set_local_node_info` stores NodeInfo in keys object
- Multiple key instances = multiple NodeInfo storage locations
- Transport reads from keys storage instead of its own storage
- Function name is misleading (says keys but takes transport handle)

**Required Changes:**
1. **Rename**: `rn_keys_set_local_node_info` → `rn_transport_set_local_node_info`
2. **Move Storage**: NodeInfo storage from keys to transport object
3. **Update Callback**: Transport callback reads from transport storage, not keys storage
4. **Update Swift**: Call `transport.setLocalNodeInfo()` instead of `keyManager.setLocalNodeInfo()`
5. **Update FFI**: Add `rn_transport_set_local_node_info` function that updates transport storage

**Files to Modify:**
- `runar-rust/runar-ffi/src/lib.rs` - Rename function, update storage location
- `runar-rust/runar-transporter/src/transport/quic_transport.rs` - Add transport-scoped storage
- `swift-ffi/Sources/SwiftFFI/SwiftFFI.swift` - Move method from FFIKeys to QuicTransport
- `swift-node/Sources/SwiftNode/SwiftNode.swift` - Call transport method instead of keys method

This architectural fix will resolve the service announcement issue by ensuring each transport has its own NodeInfo storage that gets updated correctly.
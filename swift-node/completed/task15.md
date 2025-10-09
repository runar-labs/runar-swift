GOAL indeitify all issues realate to remove action calls - test swift-node/Tests/SwiftNodeTests/RemoteNetworkTests.swift - testRemoteActionCall()

Process:
 1) INSPECT LOGS IN DETAILS AND COMPARE TO THE RUST LOGS OF THE SAME TEST /Users/rafael/dev/runar-rust/runar-node-tests/src/network/remote_test.rs TO identify where hey diverge.

 2) Every change must be 100% aligned tyo the RUST code.. every time u touch anything in swift,m first find the correponding are in the RUST code and make sure the Swift IMPL is 100% aligned, nothing more nothing less - exact same dataflow, exact same rules, parameters, functions/method body EVERYNG must match.. test setup, test steps, testa assertions.
Consider language differeces which must exist and be kept, and consider that Swift uses FFI to access Key mangers, transporter, discovery from the RUST layer and it does not ahve its own.

 3) keep iterating and fixing swift side to aligne with rust 100% until the test testRemoteActionCall() works properly - DO NOT compromise thet test. the test must be exactly like tyeh rust test at remote_test.rs

 Follow our rules .cursor/rules/code-standards.mdc


 # Task 15: Fix Remote Action Call Implementation - COMPLETED

## Summary
Fixed the remote action call implementation in Swift to 100% align with the Rust codebase, addressing critical issues with how `NetworkMessage` is constructed and passed between the FFI and Node layers.

## Issues Found

### Issue 1: Incorrect Callback Signature
- **Problem**: Swift `RequestCallback` was `(String, String, Data, String, String)` instead of receiving a complete `NetworkMessage`
- **Root Cause**: Didn't match Rust pattern where `RequestCallback = Arc<dyn Fn(NetworkMessage) -> BoxFuture<'static, Result<NetworkMessage>>>`
- **Impact**: `profilePublicKey` from `TransportRequestEvent` was never passed to the Node layer

### Issue 2: Response Deserialization Error (`invalidCategory(164)`)
- **Problem**: `executeRemoteRequest` was deserializing the entire `NetworkMessage` CBOR as `AnyValue` payload
- **Root Cause**: `transport.request()` returns the full `NetworkMessage` CBOR, not just the payload bytes
- **Impact**: Deserialization failed with `invalidCategory(164)` where `0xA4` is CBOR map tag

### Issue 3: Asynchronous Callback Not Awaiting Response
- **Problem**: `requestCallback` was using fire-and-forget `Task` and returning placeholder response
- **Root Cause**: Didn't match Rust's synchronous await pattern
- **Impact**: Response was always `{"status": "processing"}` instead of actual result

### Issue 4: Fallback Patterns in MathService
- **Problem**: `handleAdd`, `handleSubtract`, `handleMultiply`, `handleDivide` used `?? 0.0` fallbacks
- **Root Cause**: `asType()` is `async throws` but code was using sync optional chaining
- **Impact**: All operations returned `0.0 + 0.0` instead of actual calculation

## Solutions Implemented

### 1. FFI Layer (`SwiftFFI.swift`)
```swift
// OLD: Individual parameters
public typealias RequestCallback = @Sendable (String, String, Data, String, String) async -> NetworkMessage

// NEW: Complete NetworkMessage (matching Rust exactly)
public typealias RequestCallback = @Sendable (String, NetworkMessage) async -> NetworkMessage
```

**Key Change**: Construct complete `NetworkMessage` from `TransportRequestEvent`:
```swift
// Rust FFI extracts .first().unwrap_or_default() from profile_public_keys array
// Swift reverses this: empty Data -> [], non-empty Data -> [Data]
let profilePublicKeys: [Data] = event.profilePublicKey.isEmpty ? [] : [event.profilePublicKey]

let incomingMessage = NetworkMessage(
    sourceNodeId: event.sourcePeerId,
    destinationNodeId: event.destinationPeerId,
    messageType: 4, // MESSAGE_TYPE_REQUEST
    payload: NetworkMessagePayloadItem(
        path: event.path,
        payloadBytes: event.payload,
        correlationId: event.correlationId,
        networkPublicKey: nil, // Not in TransportRequestEvent; Node looks it up locally
        profilePublicKeys: profilePublicKeys
    )
)
```

### 2. Node Layer (`SwiftNode.swift`)
```swift
requestCallback: { [weak self, logger] requestId, incomingMessage in
    // Process the network request and return the response
    do {
        let responseMessage = try await handleNetworkRequest(incomingMessage)
        return responseMessage
    } catch {
        // ... proper error handling with encrypted response ...
    }
}
```

**Key Changes**:
- Callback receives complete `NetworkMessage` instead of individual parameters
- Directly `await` the response instead of fire-and-forget `Task`
- Use `incomingMessage.payload.profilePublicKeys` directly
- Node looks up `networkPublicKey` locally (matching Rust pattern)

### 3. Response Deserialization Fix
```swift
// OLD: Direct deserialization (incorrect)
let responseValue = try AnyValue.deserialize(responseBytes, keystore: keysManager)

// NEW: First decode NetworkMessage, then extract payload
let networkMessage = try CodableCBORDecoder().decode(NetworkMessage.self, from: responseBytes)
let responseValue = try AnyValue.deserialize(networkMessage.payload.payloadBytes, keystore: keysManager)
```

### 4. MathService Parameter Extraction
```swift
// OLD: Fallback pattern (hides errors)
let a = (map["a"] as? AnyValue)?.asType() as Double? ?? 0.0

// NEW: Explicit error propagation
let a: Double = try await map["a"]?.asType() ?? {
    throw ServiceRegistryError.serviceNotFound("Parameter 'a' missing")
}()
```

## Rust vs Swift Alignment

### Data Flow: Sender Side
**Rust Node → Transport:**
```rust
transport.request(
    path,
    correlation_id,
    payload_bytes,
    peer_node_id,
    Some(network_public_key),  // Looked up locally
    profile_public_keys        // From request context
)
```

**Swift Node → Transport:** ✅ Same pattern

### Data Flow: Receiver Side
**Rust Transport → Node:**
```rust
// Transport deserializes complete NetworkMessage from wire
let msg = from_slice::<NetworkMessage>(&msg_buf)?;
// Passes complete message to callback
(self.request_callback)(msg).await
```

**Swift Transport → Node:** ✅ Same pattern (after fix)

### Data Flow: Node Processing
**Rust Node:**
```rust
let profile_public_keys = msg.payload.profile_public_keys.clone();
let network_public_key = self.keys_manager.get_network_public_key_by_id(&network_id)?;
// Incoming network_public_key is IGNORED (always looked up locally)
```

**Swift Node:** ✅ Same pattern (after fix)

### FFI Layer Conversion
**Rust FFI (runar-ffi/src/lib.rs:4100-4103):**
```rust
profile_public_key: req
    .payload
    .profile_public_keys
    .first()
    .cloned()
    .unwrap_or_default(),  // Extract first key or empty
```

**Swift FFI:** ✅ Inverse operation:
```swift
let profilePublicKeys: [Data] = event.profilePublicKey.isEmpty ? [] : [event.profilePublicKey]
```

## Key Insights

1. **`networkPublicKey` is NEVER trusted from wire** - Both Rust and Swift always look it up locally based on `network_id`
2. **`profilePublicKeys` IS trusted from wire** - Passed through from sender to receiver for encryption context
3. **FFI layer converts array ↔ singular** - Rust extracts `.first()`, Swift reconstructs `[first]`
4. **No fallback patterns** - The `.unwrap_or_default()` is NOT a fallback; it's the correct handling for empty arrays

## Verification

✅ Test passes consistently: `testRemoteActionCall()`
✅ All math operations return correct results
✅ No linter errors
✅ Code formatted with SwiftFormat
✅ 100% aligned with Rust implementation

## Files Modified

1. `swift-ffi/Sources/SwiftFFI/SwiftFFI.swift`
   - Changed `RequestCallback` signature
   - Construct complete `NetworkMessage` from `TransportRequestEvent`
   
2. `swift-node/Sources/SwiftNode/SwiftNode.swift`
   - Updated callback to receive `NetworkMessage`
   - Fixed response deserialization to decode `NetworkMessage` first
   - Fixed async callback to `await` response directly
   
3. `swift-node/Tests/SwiftNodeTests/RegistryServiceTests.swift`
   - Removed `?? 0.0` fallbacks from all math operations
   - Added explicit error throwing for missing parameters

## Compliance with Code Standards

✅ No mocks, no shortcuts, no hacks
✅ Production-ready code
✅ Proper error handling (no silent failures)
✅ 100% alignment with Rust counterpart
✅ Deterministic behavior
✅ No fallbacks without justification


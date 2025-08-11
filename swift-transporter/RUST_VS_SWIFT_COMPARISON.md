# Rust vs Swift QUIC Transport Implementation Comparison

## Overview
This document provides a comprehensive comparison between the Rust (`runar-rust/runar-node/src/network/transport/quic_transport.rs`) and Swift (`swift-transporter/Sources/RunarTransporter/NetworkQuicTransporter.swift`) QUIC transport implementations. The goal is to identify all discrepancies that need to be resolved for the two implementations to communicate with each other.

## Critical Discrepancies

### 1. Message Encoding Format

#### Rust Implementation
- **Encoding**: Uses CBOR serialization with length prefixing
- **Format**: `[4-byte length][CBOR message]`
- **Code**: 
```rust
fn encode_message(msg: &NetworkMessage) -> Result<Vec<u8>, NetworkError> {
    let mut buf = serde_cbor::to_vec(msg)
        .map_err(|e| NetworkError::MessageError(format!("failed to encode cbor: {e}")))?;
    let mut framed = (buf.len() as u32).to_be_bytes().to_vec();
    framed.append(&mut buf);
    Ok(framed)
}
```

#### Swift Implementation
- **Encoding**: CBOR serialization now available with length prefixing (via SwiftCBOR)
- **Format**: `[4-byte length][CBOR message]`
- **Encoder**: `Sources/RunarTransporter/CborMessageEncoder.swift`
- **Code**:
```swift
// Produce CBOR body
let body = try CborMessageEncoder.encodeNetworkMessage(message)

// Frame: [4-byte BE length][CBOR bytes]
var framed = Data()
var len = UInt32(body.count).bigEndian
withUnsafeBytes(of: &len) { raw in
    framed.append(raw.bindMemory(to: UInt8.self))
}
framed.append(body)
```

**✅ DONE (Encoder + Test)**: Added CBOR encoder and unit test verifying the framing:
- Test: `Tests/RunarTransporterTests/CborEncodingTests.swift::testFramingAndCborEncodingOfNetworkMessage`
- Status: Test passes and validates `[4-byte length][CBOR]` plus CBOR fields.
- Next: Wire runtime send/receive to use CBOR encoder/decoder instead of the current custom binary path.

### 2. Message Structure

#### Rust NetworkMessage
```rust
pub struct NetworkMessage {
    pub source_node_id: String,
    pub destination_node_id: String,
    pub message_type: u32,  // Numeric enum
    pub payloads: Vec<NetworkMessagePayloadItem>,
}
```

#### Swift RunarNetworkMessage
```swift
public struct RunarNetworkMessage: Codable, Equatable, Sendable {
    public let sourceNodeId: String
    public let destinationNodeId: String
    public let messageType: String  // String-based
    public let payloads: [NetworkMessagePayloadItem]
    public let timestamp: Date      // Additional field
}
```

**❌ CRITICAL**: 
- `message_type` is `u32` in Rust vs `String` in Swift
- Swift has an additional `timestamp` field
- Field naming conventions differ (`source_node_id` vs `sourceNodeId`)

### 3. Message Type Constants

#### Rust Implementation
```rust
pub const MESSAGE_TYPE_DISCOVERY: u32 = 1;
pub const MESSAGE_TYPE_HEARTBEAT: u32 = 2;
pub const MESSAGE_TYPE_HANDSHAKE: u32 = 3;
pub const MESSAGE_TYPE_REQUEST: u32 = 4;
pub const MESSAGE_TYPE_RESPONSE: u32 = 5;
pub const MESSAGE_TYPE_EVENT: u32 = 6;
pub const MESSAGE_TYPE_ERROR: u32 = 7;
```

#### Swift Implementation
```swift
// In Constants.swift
public enum MessageTypes: String, CaseIterable {
    case discovery = "Discovery"
    case heartbeat = "Heartbeat"
    case handshake = "Handshake"
    case request = "Request"
    case response = "Response"
    case event = "Event"
    case error = "Error"
}
```

**✅ DONE (Mapping + Tests, not yet integrated)**:
- Implemented isolated mapping utilities between Swift message type strings and Rust u32 constants
- Tests: `MessageTypeMappingTests` cover parsing digits/names and converting to Rust `u32`
- Next: Integrate the mapping in transporter send/receive paths during Phase 4

### 4. Message Payload Structure

#### Rust NetworkMessagePayloadItem
```rust
pub struct NetworkMessagePayloadItem {
    pub path: String,
    pub value_bytes: Vec<u8>,
    pub context: Option<MessageContext>,
    pub correlation_id: String,
}
```

#### Swift NetworkMessagePayloadItem
```swift
public struct NetworkMessagePayloadItem: Codable, Equatable, Sendable {
    public let path: String
    public let valueBytes: Data
    public let correlationId: String
}
```

**✅ IN PROGRESS (Isolated codec + tests, not yet integrated)**:
- Added isolated CBOR codec/tests for payload with optional `context` matching Rust (`profile_public_key`)
- Field names use snake_case to match Rust (`value_bytes`, `correlation_id`)
- Next: integrate optional context into Swift payload model and transporter in Phase 4

### 5. Handshake Protocol

#### Rust Implementation
- **Handshake Data**: Uses `HandshakeData` struct with `NodeInfo`, `nonce`, and `ConnectionRole`
- **Format**: CBOR serialized `HandshakeData` wrapped in `NetworkMessage`
- **Path**: Uses `"handshake"` as the payload path
- **Code**:
```rust
let hs = HandshakeData {
    node_info: self.local_node_info.clone(),
    nonce: local_nonce,
    role: ConnectionRole::Initiator,
};
let payload_bytes = serde_cbor::to_vec(&hs)?;
```

#### Swift Implementation
- **Handshake Data**: Uses `RunarNodeInfo` directly
- **Format**: Custom binary format
- **Path**: Uses `"handshake"` as the payload path
- **Code**:
```swift
let handshakeMessage = RunarNetworkMessage(
    sourceNodeId: localNodeId,
    destinationNodeId: peerId,
    messageType: MessageTypes.handshake.rawValue,
    payloads: [NetworkMessagePayloadItem(
        path: "handshake",
        valueBytes: try BinaryMessageEncoder.encodeNodeInfo(localNodeInfo),
        correlationId: NodeUtils.generateCorrelationId()
    )]
)
```

**✅ IN PROGRESS (Isolated types + CBOR codec, not yet integrated)**:
- Implemented `HandshakeData` with `nodeInfo`, `nonce`, and `role` (initiator/responder)
- Added CBOR encoder/decoder and unit test `HandshakeCborTests`
- Next: integrate handshake flow and nonce/role usage in transporter during Phase 4

### 6. Connection Management

#### Rust Implementation
- **Peer State**: Complex `PeerState` with connection activation, nonces, and connection roles
- **Connection Deduplication**: Uses nonce-based conflict resolution
- **Activation**: Connections become active only after handshake completion
- **Code**:
```rust
struct PeerState {
    connection: Arc<quinn::Connection>,
    connection_id: usize,
    node_info_version: i64,
    initiator_peer_id: String,
    initiator_nonce: u64,
    responder_peer_id: String,
    responder_nonce: u64,
    activation_tx: watch::Sender<bool>,
    activation_rx: watch::Receiver<bool>,
}
```

#### Swift Implementation
- **Peer State**: Simple `PeerState` with basic connection info
- **Connection Deduplication**: Basic IP-based deduplication
- **Activation**: Connections start receiving immediately
- **Code**:
```swift
public class PeerState {
    public let connection: NWConnection
    public let address: String
    public let peerId: String
    public let queue: DispatchQueue
}
```

**❌ CRITICAL**: 
- Swift lacks the sophisticated connection state management
- No nonce-based conflict resolution
- No connection activation mechanism
- Different peer identification strategies

### 7. Stream Management

#### Rust Implementation
- **Stream Types**: Uses Quinn's `RecvStream` and `SendStream`
- **Stream Lifecycle**: Opens fresh bidirectional streams for each request
- **Stream Handling**: Dedicated loops for uni/bi-directional streams
- **Code**:
```rust
let (mut send, mut recv) = conn.open_bi().await?;
self.write_message(&mut send, &msg).await?;
send.finish().await?;
```

#### Swift Implementation
- **Stream Types**: Uses Network.framework's `NWConnection`
- **Stream Lifecycle**: Single connection with message buffering
- **Stream Handling**: Continuous receive loop with message parsing
- **Code**:
```swift
connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
    // Process received data
}
```

**❌ CRITICAL**: 
- Different stream abstraction layers
- Different message handling patterns
- Swift doesn't use separate streams for requests

### 8. Error Handling

#### Rust Implementation
- **Error Types**: Comprehensive `NetworkError` enum
- **Error Context**: Detailed error messages with context
- **Code**:
```rust
#[derive(Error, Debug)]
pub enum NetworkError {
    #[error("Connection error: {0}")]
    ConnectionError(String),
    #[error("Message error: {0}")]
    MessageError(String),
    #[error("Transport error: {0}")]
    TransportError(String),
    // ... more variants
}
```

#### Swift Implementation
- **Error Types**: `RunarTransportError` enum
- **Error Context**: Basic error messages
- **Code**:
```swift
public enum RunarTransportError: Error, LocalizedError {
    case configurationError(String)
    case connectionError(String)
    case messageError(String)
    // ... more cases
}
```

**⚠️ MODERATE**: 
- Different error type names
- Some error variants don't match
- Different error context handling

### 9. Certificate and TLS Handling

#### Rust Implementation
- **Certificate Verification**: Custom `NodeIdServerNameVerifier`
- **TLS Configuration**: Uses `rustls` with custom configs
- **Code**:
```rust
impl rustls::client::danger::ServerCertVerifier for NodeIdServerNameVerifier {
    fn verify_server_cert(&self, end_entity: &CertificateDer<'_>, ...) -> Result<...> {
        // Custom verification logic
    }
}
```

#### Swift Implementation
- **Certificate Verification**: Uses Network.framework's built-in TLS
- **TLS Configuration**: Basic TLS setup with identity
- **Code**:
```swift
let tlsOptions = NWProtocolTLS.Options()
tlsOptions.identity = identity
```

**⚠️ MODERATE**: 
- Different TLS libraries and verification approaches
- Swift lacks custom certificate verification logic
- Different security model assumptions

### 10. Message Processing Flow

#### Rust Implementation
- **Request Flow**: Opens new stream → writes request → reads response → closes stream
- **Publish Flow**: Opens unidirectional stream → writes message → closes stream
- **Code**:
```rust
async fn request_inner(&self, conn: &quinn::Connection, msg: &NetworkMessage) -> Result<NetworkMessage, NetworkError> {
    let (mut send, mut recv) = conn.open_bi().await?;
    self.write_message(&mut send, &msg).await?;
    send.finish().await?;
    let response = self.read_message(&mut recv).await?;
    Ok(response)
}
```

#### Swift Implementation
- **Request Flow**: Sends message on existing connection → waits for response
- **Publish Flow**: Sends message on existing connection
- **Code**:
```swift
public func sendMessage(_ message: RunarNetworkMessage, to peerId: String) async throws {
    guard let peerState = connectionPool.getPeer(peerId) else {
        throw RunarTransportError.peerNotConnected(peerId)
    }
    try await sendMessage(message, on: peerState.connection)
}
```

**❌ CRITICAL**: 
- Different message flow patterns
- Swift doesn't use separate streams per request
- Different connection lifecycle management

## Required Changes for Interoperability

### 1. Message Encoding (HIGHEST PRIORITY)
- **Swift**: Replace custom binary format with CBOR serialization
- **Swift**: Add CBOR dependency and implement `serde_cbor` equivalent
- **Swift**: Update message encoding/decoding to match Rust format

### 2. Message Structure Alignment (HIGH PRIORITY)
- **Swift**: Change `messageType` from `String` to `UInt32`
- **Swift**: Remove `timestamp` field from `RunarNetworkMessage`
- **Swift**: Add `context` field to `NetworkMessagePayloadItem`
- **Swift**: Align field naming conventions with Rust

### 3. Message Type Constants (HIGH PRIORITY)
- **Swift**: Replace string-based message types with numeric constants
- **Swift**: Implement mapping: `MESSAGE_TYPE_HANDSHAKE = 3`, etc.
- **Swift**: Update all message type references throughout the codebase

### 4. Handshake Protocol (HIGH PRIORITY)
- **Swift**: Implement `HandshakeData` struct matching Rust
- **Swift**: Add nonce generation and connection role handling
- **Swift**: Update handshake message format to match Rust

### 5. Connection Management (MEDIUM PRIORITY)
- **Swift**: Enhance `PeerState` with activation mechanism
- **Swift**: Implement nonce-based connection conflict resolution
- **Swift**: Add connection activation state management

### 6. Stream Management (MEDIUM PRIORITY)
- **Swift**: Consider implementing stream-based message handling
- **Swift**: Or ensure single-connection approach is compatible with Rust's stream expectations

### 7. Error Handling (LOW PRIORITY)
- **Swift**: Align error types with Rust `NetworkError`
- **Swift**: Ensure error context is preserved appropriately

### 8. Certificate Handling (LOW PRIORITY)
- **Swift**: Implement custom certificate verification if needed
- **Swift**: Ensure TLS configuration is compatible

## Implementation Strategy

### Phase 0: Isolated Components + Unit Tests (no transporter wiring)
1. Implement CBOR encoder/decoder utilities for messages and node info with unit tests
   - Status: CBOR message encoder + framing test added and passing (see `CborEncodingTests`)
2. Implement numeric message type mapping utilities (u32) with unit tests
3. Define Rust-compatible `HandshakeData` (node_info, nonce, role) and implement CBOR codec with unit tests
4. Extend payload model to support optional `context`; provide CBOR codec + unit tests
5. Provide standalone framing helpers (read/write 4-byte BE length) with unit tests
6. Design connection/peer state data structures (activation, nonce dedupe) decoupled from `NWConnection`; unit-test state transitions

### Phase 1: Core Message Compatibility
1. Align message structures and types
2. Update handshake protocol

### Phase 2: Protocol Compatibility
1. Implement connection state management
2. Align message flow patterns
3. Test basic message exchange

### Phase 3: Advanced Features
1. Implement stream-based handling (if needed)
2. Enhance error handling
3. Optimize performance and reliability

### Phase 4: Integration and Refactor Transporter (deferred tasks)
1. Replace `BinaryMessageEncoder` with CBOR encoder/decoder in `NetworkQuicTransporter` send/receive paths
2. Ensure framing remains `[4-byte BE length][CBOR]` and unify buffering/parse paths
3. Migrate message type usage to numeric constants throughout transporter and tests
4. Integrate `HandshakeData` (nonce + role) and update handshake flow accordingly
5. Integrate connection activation and nonce-based deduplication into `ConnectionPool`/`PeerState`
6. Remove legacy binary encoding and related code paths after tests pass

## Testing Strategy

### Unit Tests
- Test message encoding/decoding compatibility
- Test handshake protocol compatibility
- Test error handling alignment

### Integration Tests
- Test Swift client ↔ Rust server communication
- Test Rust client ↔ Swift server communication
- Test bidirectional message exchange

### End-to-End Tests
- Test complete request/response cycles
- Test connection lifecycle management
- Test error scenarios and recovery

## Conclusion

The current Swift implementation has significant architectural and protocol differences from the Rust implementation that will prevent any meaningful communication between the two. The highest priority items are:

1. **Message encoding format** - Must use CBOR instead of custom binary
2. **Message structure** - Must align field types and names
3. **Message types** - Must use numeric constants instead of strings
4. **Handshake protocol** - Must implement the same data structures and flow

Addressing these critical discrepancies will require substantial refactoring of the Swift implementation, but it's necessary for interoperability. The connection management and stream handling differences are less critical but should be addressed for full compatibility.

Once these changes are implemented, both implementations should be able to communicate effectively, enabling cross-platform deployment and testing scenarios.

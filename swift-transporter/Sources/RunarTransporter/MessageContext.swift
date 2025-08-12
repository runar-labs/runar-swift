import Foundation

/// Matches Rust `MessageContext` in transport/mod.rs
public struct MessageContextSwift: Equatable, Hashable {
    public let profilePublicKey: Data

    public init(profilePublicKey: Data) {
        self.profilePublicKey = profilePublicKey
    }
}

/// Payload model with optional context, for CBOR compatibility tests (isolated from transporter wiring)
public struct PayloadWithContext: Equatable, Hashable {
    public let path: String
    public let valueBytes: Data
    public let correlationId: String
    public let context: MessageContextSwift?

    public init(path: String, valueBytes: Data, correlationId: String, context: MessageContextSwift?) {
        self.path = path
        self.valueBytes = valueBytes
        self.correlationId = correlationId
        self.context = context
    }
}

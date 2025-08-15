import Foundation

// MARK: - Message Type Constants

/// Constants for message types used in the Runar network
/// Matches the Rust implementation with numeric constants
public enum MessageTypes {
    /// Discovery message type (1)
    public static let discovery = "1"

    /// Heartbeat message type (2)
    public static let heartbeat = "2"

    /// Handshake message type (3) - matches Rust MESSAGE_TYPE_HANDSHAKE
    public static let handshake = "3"

    /// Request message type (4) - matches Rust MESSAGE_TYPE_REQUEST
    public static let request = "4"

    /// Response message type (5) - matches Rust MESSAGE_TYPE_RESPONSE
    public static let response = "5"

    /// Event message type (6) - matches Rust MESSAGE_TYPE_EVENT
    public static let event = "6"

    /// Error message type (7) - matches Rust MESSAGE_TYPE_ERROR
    public static let error = "7"

    /// Node info update message type (8)
    public static let nodeInfoUpdate = "8"

    /// Node info handshake response message type (9)
    public static let nodeInfoHandshakeResponse = "9"

    /// Node info handshake message type (3) - alias for HANDSHAKE
    public static let nodeInfoHandshake = "3"
}

import Foundation

// MARK: - Message Type Constants

/// Constants for message types used in the Runar network
/// Matches the Rust implementation with numeric constants
public enum MessageTypes {
    /// Discovery message type (1)
    public static let discovery = "1"

    /// Heartbeat message type (2)
    public static let heartbeat = "2"

    /// Announcement message type (3)
    public static let announcement = "3"

    /// Handshake message type (4)
    public static let handshake = "4"

    /// Request message type (5)
    public static let request = "5"

    /// Response message type (6)
    public static let response = "6"

    /// Event message type (7)
    public static let event = "7"

    /// Error message type (8)
    public static let error = "8"

    /// Node info update message type (9)
    public static let nodeInfoUpdate = "9"

    /// Node info handshake response message type (10)
    public static let nodeInfoHandshakeResponse = "10"

    /// Node info handshake message type (4) - alias for HANDSHAKE
    public static let nodeInfoHandshake = "4"
}

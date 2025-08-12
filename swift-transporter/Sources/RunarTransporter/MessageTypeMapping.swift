import Foundation

/// Semantic message types used across implementations
public enum SemanticMessageType: CaseIterable, Equatable, Hashable {
    case discovery
    case heartbeat
    case handshake
    case request
    case response
    case event
    case error
    // Non-Rust-core/Swift-only extras (kept for completeness in mapping layer)
    case announcement
    case nodeInfoUpdate
    case nodeInfoHandshakeResponse
}

/// Rust u32 constants for core message types
public enum RustMessageType {
    public static let discovery: UInt32 = 1
    public static let heartbeat: UInt32 = 2
    public static let handshake: UInt32 = 3
    public static let request: UInt32 = 4
    public static let response: UInt32 = 5
    public static let event: UInt32 = 6
    public static let error: UInt32 = 7
}

public enum MessageTypeMappingError: Error, Equatable {
    case unknownType(String)
}

/// Utility to convert between current Swift string message types and Rust u32 constants
public enum MessageTypeMapping {
    /// Parse current Swift message type string into a semantic type
    /// Current Swift constants (Constants.swift):
    /// 1=DISCOVERY, 2=HEARTBEAT, 3=ANNOUNCEMENT, 4=HANDSHAKE, 5=REQUEST, 6=RESPONSE, 7=EVENT, 8=ERROR, 9=NODE_INFO_UPDATE, 10=NODE_INFO_HANDSHAKE_RESPONSE
    public static func parseSwiftString(_ value: String) throws -> SemanticMessageType {
        switch value {
        case "1": return .discovery
        case "2": return .heartbeat
        case "3": return .announcement
        case "4": return .handshake
        case "5": return .request
        case "6": return .response
        case "7": return .event
        case "8": return .error
        case "9": return .nodeInfoUpdate
        case "10": return .nodeInfoHandshakeResponse
        default:
            // Also accept legacy textual names if they appear
            switch value.lowercased() {
            case "discovery": return .discovery
            case "heartbeat": return .heartbeat
            case "handshake": return .handshake
            case "request": return .request
            case "response": return .response
            case "event": return .event
            case "error": return .error
            case "announcement": return .announcement
            default: throw MessageTypeMappingError.unknownType(value)
            }
        }
    }

    /// Convert a semantic type into the Rust u32 constant
    public static func toRustU32(_ semantic: SemanticMessageType) throws -> UInt32 {
        switch semantic {
        case .discovery: return RustMessageType.discovery
        case .heartbeat: return RustMessageType.heartbeat
        case .handshake: return RustMessageType.handshake
        case .request: return RustMessageType.request
        case .response: return RustMessageType.response
        case .event: return RustMessageType.event
        case .error: return RustMessageType.error
        case .announcement, .nodeInfoUpdate, .nodeInfoHandshakeResponse:
            // Not defined in Rust core mapping; treat as unknown in Rust numeric space
            throw MessageTypeMappingError.unknownType(String(describing: semantic))
        }
    }

    /// Convert Rust u32 constant into semantic type
    public static func fromRustU32(_ value: UInt32) throws -> SemanticMessageType {
        switch value {
        case RustMessageType.discovery: return .discovery
        case RustMessageType.heartbeat: return .heartbeat
        case RustMessageType.handshake: return .handshake
        case RustMessageType.request: return .request
        case RustMessageType.response: return .response
        case RustMessageType.event: return .event
        case RustMessageType.error: return .error
        default: throw MessageTypeMappingError.unknownType("u32:\\(value)")
        }
    }

    /// Convert Rust u32 constant into current Swift string constant
    public static func toSwiftString(fromRustU32 value: UInt32) throws -> String {
        let semantic = try fromRustU32(value)
        return toSwiftString(semantic)
    }

    /// Convert a semantic type back to current Swift string constant used by `MessageTypes`
    public static func toSwiftString(_ semantic: SemanticMessageType) -> String {
        switch semantic {
        case .discovery: return "1"
        case .heartbeat: return "2"
        case .announcement: return "3"
        case .handshake: return "4"
        case .request: return "5"
        case .response: return "6"
        case .event: return "7"
        case .error: return "8"
        case .nodeInfoUpdate: return "9"
        case .nodeInfoHandshakeResponse: return "10"
        }
    }

    /// Convenience: convert current Swift string to Rust u32 for core types
    public static func swiftStringToRustU32(_ value: String) throws -> UInt32 {
        let semantic = try parseSwiftString(value)
        return try toRustU32(semantic)
    }
}

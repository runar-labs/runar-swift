import Foundation

// MARK: - FFI Callback Types

/// Response callback type: called when request succeeds
/// Matches Rust: `pub type ResponseCallback = extern "C" fn(payload_bytes: *const u8, payload_len: usize);`
public typealias ResponseCallback = @convention(c) (UnsafePointer<UInt8>, UInt) -> Void

/// Error callback type: called when request fails
/// Matches Rust: `pub type ErrorCallback = extern "C" fn(error_code: u32, error_message: *const c_char);`
public typealias ErrorCallback = @convention(c) (UInt32, UnsafePointer<CChar>) -> Void

// MARK: - FFI Function Signatures

/// Transporter request function signature
/// Matches Rust: `transporter_request(...) -> i32`
public typealias TransporterRequestFunction = @convention(c) (
    UnsafePointer<CChar>,      // topic
    UnsafePointer<UInt8>,      // payload_bytes
    UInt,                      // payload_len
    UnsafePointer<CChar>,      // peer_node_id
    UnsafePointer<UInt8>,      // profile_public_key
    UInt,                      // profile_key_len
    ResponseCallback,           // response_callback
    ErrorCallback               // error_callback
) -> Int32

// MARK: - Error Codes

/// Standard error codes for FFI communication
public enum FFIErrorCode: UInt32, CaseIterable {
    case success = 0
    case invalidPointer = 1
    case serializationError = 2
    case deserializationError = 3
    case callbackError = 4
    case memoryError = 5
    case unknownError = 999
    
    public var description: String {
        switch self {
        case .success:
            return "Success"
        case .invalidPointer:
            return "Invalid pointer provided"
        case .serializationError:
            return "Serialization error"
        case .deserializationError:
            return "Deserialization error"
        case .callbackError:
            return "Callback execution error"
        case .memoryError:
            return "Memory allocation error"
        case .unknownError:
            return "Unknown error occurred"
        }
    }
}

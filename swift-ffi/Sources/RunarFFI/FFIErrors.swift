import CRunarFFI
import Foundation

/// Swift FFI Error types - mirroring Rust error codes exactly
public enum FFIError: LocalizedError {
    case nullArgument(String)
    case invalidHandle(String)
    case notInitialized
    case wrongManagerType(String)
    case operationFailed(String)
    case serializationFailed(String)
    case keystoreFailed(String)
    case memoryAllocation(String)
    case lockError(String)
    case invalidUTF8(String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case let .nullArgument(msg):
            return "Null argument: \(msg)"
        case let .invalidHandle(msg):
            return "Invalid handle: \(msg)"
        case .notInitialized:
            return "FFI instance not initialized"
        case let .wrongManagerType(msg):
            return "Wrong manager type: \(msg)"
        case let .operationFailed(msg):
            return "Operation failed: \(msg)"
        case let .serializationFailed(msg):
            return "Serialization failed: \(msg)"
        case let .keystoreFailed(msg):
            return "Keystore operation failed: \(msg)"
        case let .memoryAllocation(msg):
            return "Memory allocation failed: \(msg)"
        case let .lockError(msg):
            return "Lock acquisition failed: \(msg)"
        case let .invalidUTF8(msg):
            return "Invalid UTF-8 string: \(msg)"
        case let .invalidArgument(msg):
            return "Invalid argument: \(msg)"
        }
    }

    /// Error code constants - matching Rust error codes exactly
    public var errorCode: Int32 {
        switch self {
        case .nullArgument: return 1
        case .invalidHandle: return 2
        case .notInitialized: return 3
        case .wrongManagerType: return 4
        case .operationFailed: return 5
        case .serializationFailed: return 6
        case .keystoreFailed: return 7
        case .memoryAllocation: return 8
        case .lockError: return 9
        case .invalidUTF8: return 10
        case .invalidArgument: return 11
        }
    }

    /// Legacy constructor for backwards compatibility
    public init(code: Int32, message: String) {
        self = Self.errorFromCode(code, message: message)
    }

    private static func errorFromCode(_ code: Int32, message: String) -> FFIError {
        switch code {
        case 1: return .nullArgument(message)
        case 2: return .invalidHandle(message)
        case 3: return .notInitialized
        case 4: return .wrongManagerType(message)
        case 5: return .operationFailed(message)
        case 6: return .serializationFailed(message)
        case 7: return .keystoreFailed(message)
        case 8: return .memoryAllocation(message)
        case 9: return .lockError(message)
        case 10: return .invalidUTF8(message)
        case 11: return .invalidArgument(message)
        default: return .operationFailed("Unknown error code: \(code), message: \(message)")
        }
    }
}

@inline(__always)
func withRnError<T>(_ body: (UnsafeMutablePointer<RNAPIRnError>) -> T) -> (T, FFIError?) {
    var err = RNAPIRnError(code: 0, message: nil)
    let result = withUnsafeMutablePointer(to: &err) { ptr in
        body(ptr)
    }
    if err.code != 0 {
        let msg = err.message.map { String(cString: $0) } ?? "Unknown error"
        if let cstr = err.message { rn_string_free(cstr) }
        return (result, FFIError(code: err.code, message: msg))
    }
    return (result, nil)
}

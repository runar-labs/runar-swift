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
            "Null argument: \(msg)"
        case let .invalidHandle(msg):
            "Invalid handle: \(msg)"
        case .notInitialized:
            "FFI instance not initialized"
        case let .wrongManagerType(msg):
            "Wrong manager type: \(msg)"
        case let .operationFailed(msg):
            "Operation failed: \(msg)"
        case let .serializationFailed(msg):
            "Serialization failed: \(msg)"
        case let .keystoreFailed(msg):
            "Keystore operation failed: \(msg)"
        case let .memoryAllocation(msg):
            "Memory allocation failed: \(msg)"
        case let .lockError(msg):
            "Lock acquisition failed: \(msg)"
        case let .invalidUTF8(msg):
            "Invalid UTF-8 string: \(msg)"
        case let .invalidArgument(msg):
            "Invalid argument: \(msg)"
        }
    }

    /// Error code constants - matching Rust error codes exactly
    public var errorCode: Int32 {
        switch self {
        case .nullArgument: 1
        case .invalidHandle: 2
        case .notInitialized: 3
        case .wrongManagerType: 4
        case .operationFailed: 5
        case .serializationFailed: 6
        case .keystoreFailed: 7
        case .memoryAllocation: 8
        case .lockError: 9
        case .invalidUTF8: 10
        case .invalidArgument: 11
        }
    }

    /// Legacy constructor for backwards compatibility
    public init(code: Int32, message: String) {
        self = Self.errorFromCode(code, message: message)
    }

    private static func errorFromCode(_ code: Int32, message: String) -> FFIError {
        let errorMap: [Int32: (String) -> FFIError] = [
            1: { .nullArgument($0) },
            2: { .invalidHandle($0) },
            3: { _ in .notInitialized },
            4: { .wrongManagerType($0) },
            5: { .operationFailed($0) },
            6: { .serializationFailed($0) },
            7: { .keystoreFailed($0) },
            8: { .memoryAllocation($0) },
            9: { .lockError($0) },
            10: { .invalidUTF8($0) },
            11: { .invalidArgument($0) },
        ]

        if let errorConstructor = errorMap[code] {
            return errorConstructor(message)
        } else {
            return .operationFailed("Unknown error code: \(code), message: \(message)")
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

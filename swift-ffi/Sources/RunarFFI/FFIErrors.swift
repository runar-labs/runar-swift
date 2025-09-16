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

    // CA-specific error codes
    case caNodeNotInitialized(String)
    case caServerNotRunning(String)
    case caClientConnectionFailed(String)
    case certificateValidationFailed(String)
    case profileKeyNotFound(String)
    case enrollmentTokenInvalid(String)
    case rateLimitExceeded(String)
    case adminNotAuthorized(String)
    case certificateCreationFailed(String)
    case certificateSkiExtractionFailed(String)
    case certificateSerialExtractionFailed(String)
    case enrollmentTokenGenerationFailed(String)
    case mobileResponseConversionFailed(String)
    case profileKeyEncryptionFailed(String)
    case profileKeyDecryptionFailed(String)
    case caClientConfigurationFailed(String)
    case crlGenerationFailed(String)

    // Logger-specific error codes
    case loggerAlreadyInitialized(String)
    case loggerNodeIdAlreadySet(String)
    case loggerInvalidNodeId(String)
    case loggerInvalidLevel(String)

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
        // CA-specific error descriptions
        case let .caNodeNotInitialized(msg):
            "CA Node not initialized: \(msg)"
        case let .caServerNotRunning(msg):
            "CA Server not running: \(msg)"
        case let .caClientConnectionFailed(msg):
            "CA Client connection failed: \(msg)"
        case let .certificateValidationFailed(msg):
            "Certificate validation failed: \(msg)"
        case let .profileKeyNotFound(msg):
            "Profile key not found: \(msg)"
        case let .enrollmentTokenInvalid(msg):
            "Enrollment token invalid: \(msg)"
        case let .rateLimitExceeded(msg):
            "Rate limit exceeded: \(msg)"
        case let .adminNotAuthorized(msg):
            "Admin not authorized: \(msg)"
        case let .certificateCreationFailed(msg):
            "Certificate creation failed: \(msg)"
        case let .certificateSkiExtractionFailed(msg):
            "Certificate SKI extraction failed: \(msg)"
        case let .certificateSerialExtractionFailed(msg):
            "Certificate serial extraction failed: \(msg)"
        case let .enrollmentTokenGenerationFailed(msg):
            "Enrollment token generation failed: \(msg)"
        case let .mobileResponseConversionFailed(msg):
            "Mobile response conversion failed: \(msg)"
        case let .profileKeyEncryptionFailed(msg):
            "Profile key encryption failed: \(msg)"
        case let .profileKeyDecryptionFailed(msg):
            "Profile key decryption failed: \(msg)"
        case let .caClientConfigurationFailed(msg):
            "CA Client configuration failed: \(msg)"
        case let .crlGenerationFailed(msg):
            "CRL generation failed: \(msg)"
        // Logger-specific error descriptions
        case let .loggerAlreadyInitialized(msg):
            "Logger already initialized: \(msg)"
        case let .loggerNodeIdAlreadySet(msg):
            "Logger node ID already set: \(msg)"
        case let .loggerInvalidNodeId(msg):
            "Invalid logger node ID: \(msg)"
        case let .loggerInvalidLevel(msg):
            "Invalid logger level: \(msg)"
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
        case .memoryAllocation: 12
        case .lockError: 9
        case .invalidUTF8: 10
        case .invalidArgument: 11
        // CA-specific error codes
        case .caNodeNotInitialized: 1001
        case .caServerNotRunning: 1002
        case .caClientConnectionFailed: 1003
        case .certificateValidationFailed: 1004
        case .profileKeyNotFound: 1005
        case .enrollmentTokenInvalid: 1006
        case .rateLimitExceeded: 1007
        case .adminNotAuthorized: 1008
        case .certificateCreationFailed: 1009
        case .certificateSkiExtractionFailed: 1010
        case .certificateSerialExtractionFailed: 1011
        case .enrollmentTokenGenerationFailed: 1012
        case .mobileResponseConversionFailed: 1013
        case .profileKeyEncryptionFailed: 1014
        case .profileKeyDecryptionFailed: 1015
        case .caClientConfigurationFailed: 1016
        case .crlGenerationFailed: 1017
        // Logger-specific error codes
        case .loggerAlreadyInitialized: 1020
        case .loggerNodeIdAlreadySet: 1021
        case .loggerInvalidNodeId: 1022
        case .loggerInvalidLevel: 1023
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
            12: { .memoryAllocation($0) },
            9: { .lockError($0) },
            10: { .invalidUTF8($0) },
            11: { .invalidArgument($0) },

            // CA-specific error codes
            1001: { .caNodeNotInitialized($0) },
            1002: { .caServerNotRunning($0) },
            1003: { .caClientConnectionFailed($0) },
            1004: { .certificateValidationFailed($0) },
            1005: { .profileKeyNotFound($0) },
            1006: { .enrollmentTokenInvalid($0) },
            1007: { .rateLimitExceeded($0) },
            1008: { .adminNotAuthorized($0) },
            1009: { .certificateCreationFailed($0) },
            1010: { .certificateSkiExtractionFailed($0) },
            1011: { .certificateSerialExtractionFailed($0) },
            1012: { .enrollmentTokenGenerationFailed($0) },
            1013: { .mobileResponseConversionFailed($0) },
            1014: { .profileKeyEncryptionFailed($0) },
            1015: { .profileKeyDecryptionFailed($0) },
            1016: { .caClientConfigurationFailed($0) },
            1017: { .crlGenerationFailed($0) },

            // Logger-specific error codes
            1020: { .loggerAlreadyInitialized($0) },
            1021: { .loggerNodeIdAlreadySet($0) },
            1022: { .loggerInvalidNodeId($0) },
            1023: { .loggerInvalidLevel($0) },
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

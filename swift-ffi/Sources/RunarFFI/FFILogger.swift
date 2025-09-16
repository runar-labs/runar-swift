import Foundation

/// Log levels matching the Rust FFI implementation
/// Maps to the same numeric values as the Rust `rn_set_log_level` function
@available(macOS 11.0, *)
public enum LogLevel: Int32, CaseIterable {
    case off = 0
    case error = 1
    case warn = 2
    case info = 3
    case debug = 4
    case trace = 5

    /// Human-readable description of the log level
    public var description: String {
        switch self {
        case .off: "OFF"
        case .error: "ERROR"
        case .warn: "WARN"
        case .info: "INFO"
        case .debug: "DEBUG"
        case .trace: "TRACE"
        }
    }
}

/// Standalone FFI Logger functions
/// These are global FFI functions, not related to keys
@available(macOS 11.0, *)
public final class FFILogger {
    // MARK: - Simple Logger Functions (No Error Handling)

    /// Set the log level for the FFI (simple version)
    /// - Parameter level: Log level enum
    public static func setLogLevel(_ level: LogLevel) {
        rn_set_log_level(level.rawValue)
    }

    /// Set the log level for the FFI (simple version) - legacy numeric support
    /// - Parameter level: Log level (0=Off, 1=Error, 2=Warn, 3=Info, 4=Debug, 5=Trace)
    @available(*, deprecated, message: "Use setLogLevel(_ level: LogLevel) instead")
    public static func setLogLevel(_ level: Int32) {
        rn_set_log_level(level)
    }

    // MARK: - Advanced Logger Functions (With Error Handling)

    /// Set the node ID on the global logger
    /// - Parameter nodeId: Node ID to set on the logger
    /// - Throws: FFIError if the operation fails
    public static func setLoggerNodeId(_ nodeId: String) throws {
        let (_, err) = withRnError { errPtr in
            nodeId.withCString { nodeIdCStr in
                rn_set_logger_node_id(nodeIdCStr, errPtr)
            }
        }
        if let error = err { throw error }
    }
}

// MARK: - FFI Function Declarations

/// Simple log level setter (no error handling)
@_implementationOnly import func CRunarFFI.rn_set_log_level

/// Advanced logger functions (with error handling)
@_implementationOnly import func CRunarFFI.rn_set_logger_node_id

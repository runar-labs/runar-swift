import Foundation

/// Standalone FFI Logger functions
/// These are global FFI functions, not related to keys
@available(macOS 11.0, *)
public final class FFILogger {
    
    // MARK: - Simple Logger Functions (No Error Handling)
    
    /// Set the log level for the FFI (simple version)
    /// - Parameter level: Log level (0=Off, 1=Error, 2=Warn, 3=Info, 4=Debug, 5=Trace)
    public static func setLogLevel(_ level: Int32) {
        rn_set_log_level(level)
    }
    
    // MARK: - Advanced Logger Functions (With Error Handling)
    
    /// Set the global logger level with error handling
    /// - Parameter level: Log level (0=Off, 1=Error, 2=Warn, 3=Info, 4=Debug, 5=Trace)
    /// - Throws: FFIError if the operation fails
    public static func setLoggerLevel(_ level: Int32) throws {
        let (_, err) = withRnError { errPtr in
            rn_set_logger_level(level, errPtr)
        }
        if let error = err { throw error }
    }
    
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
@_implementationOnly import func CRunarFFI.rn_set_logger_level
@_implementationOnly import func CRunarFFI.rn_set_logger_node_id

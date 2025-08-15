import Foundation
import os.log

/// Simple logger wrapper that ensures messages are visible in tests
/// Matches the Rust logging approach with context awareness
@available(macOS 12.0, iOS 15.0, *)
public class RunarLogger {
    private let subsystem: String
    private let category: String
    private let osLogger: Logger

    public init(subsystem: String = "com.runar", category: String = "default") {
        self.subsystem = subsystem
        self.category = category
        osLogger = Logger(subsystem: subsystem, category: category)
    }
    
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    public func debug(_ message: String) {
        let timestampedMessage = "[\(timestamp())] \(message)"
        osLogger.debug("\(timestampedMessage)")
        print("[DEBUG] \(timestampedMessage)")
    }

    public func info(_ message: String) {
        let timestampedMessage = "[\(timestamp())] \(message)"
        osLogger.info("\(timestampedMessage)")
        print("[INFO] \(timestampedMessage)")
    }

    public func warning(_ message: String) {
        let timestampedMessage = "[\(timestamp())] \(message)"
        osLogger.warning("\(timestampedMessage)")
        print("[WARNING] \(timestampedMessage)")
    }

    public func error(_ message: String) {
        let timestampedMessage = "[\(timestamp())] \(message)"
        osLogger.error("\(timestampedMessage)")
        print("[ERROR] \(timestampedMessage)")
    }

    public func critical(_ message: String) {
        let timestampedMessage = "[\(timestamp())] \(message)"
        osLogger.critical("\(timestampedMessage)")
        print("[CRITICAL] \(timestampedMessage)")
    }
}

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

    public func debug(_ message: String) {
        osLogger.debug("\(message)")
        print("[DEBUG] \(message)")
    }

    public func info(_ message: String) {
        osLogger.info("\(message)")
        print("[INFO] \(message)")
    }

    public func warning(_ message: String) {
        osLogger.warning("\(message)")
        print("[WARNING] \(message)")
    }

    public func error(_ message: String) {
        osLogger.error("\(message)")
        print("[ERROR] \(message)")
    }

    public func critical(_ message: String) {
        osLogger.critical("\(message)")
        print("[CRITICAL] \(message)")
    }
}

import Foundation
import os

// MARK: - Logging Types

public enum Component: String, Sendable {
    case service = "SERVICE"
    case registry = "REGISTRY"
    case transporter = "TRANSPORTER"
    case serializer = "SERIALIZER"
    case node = "NODE"
    case custom = "CUSTOM"

    public var displayName: String {
        switch self {
        case .service: "Service"
        case .registry: "Registry"
        case .transporter: "Transporter"
        case .serializer: "Serializer"
        case .node: "Node"
        case .custom: "Custom"
        }
    }
}

public enum LogLevel: String, Sendable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

public struct LoggingConfig: Sendable {
    public let level: LogLevel
    public let includeTimestamp: Bool
    public let includeComponent: Bool
    public let includeContext: Bool

    public init(
        level: LogLevel = .info,
        includeTimestamp: Bool = true,
        includeComponent: Bool = true,
        includeContext: Bool = true
    ) {
        self.level = level
        self.includeTimestamp = includeTimestamp
        self.includeComponent = includeComponent
        self.includeContext = includeContext
    }
}

// MARK: - Logger Implementation

public final class RunarLogger: Sendable {
    private let component: Component
    private let config: LoggingConfig
    private let context: String?

    public init(component: Component, config: LoggingConfig = LoggingConfig(), context: String? = nil) {
        self.component = component
        self.config = config
        self.context = context
    }

    public static func newRoot(component: Component, config: LoggingConfig = LoggingConfig()) -> RunarLogger {
        RunarLogger(component: component, config: config)
    }

    public func child(component: Component) -> RunarLogger {
        RunarLogger(component: component, config: config, context: context)
    }

    public func trace(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(level: .trace, message: message, file: file, line: line, function: function)
    }

    public func debug(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(level: .debug, message: message, file: file, line: line, function: function)
    }

    public func info(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(level: .info, message: message, file: file, line: line, function: function)
    }

    public func warning(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(level: .warning, message: message, file: file, line: line, function: function)
    }

    public func error(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(level: .error, message: message, file: file, line: line, function: function)
    }

    private func log(level: LogLevel, message: String, file _: String, line _: Int, function _: String) {
        guard shouldLog(level: level) else { return }

        var parts: [String] = []

        if config.includeTimestamp {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            parts.append("[\(timestamp)]")
        }

        parts.append("[\(level.rawValue)]")

        if config.includeComponent && component != .custom {
            parts.append("[\(component.displayName)]")
        }

        if config.includeContext, let context {
            parts.append("[\(context)]")
        }

        parts.append(message)

        let logMessage = parts.joined(separator: " ")

        #if DEBUG
            print(logMessage)
        #else
            // In production, use os_log or other logging framework
            os_log("%{public}@", log: .default, type: .default, logMessage)
        #endif
    }

    private func shouldLog(level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.trace, .debug, .info, .warning, .error]
        guard let currentIndex = levels.firstIndex(of: config.level),
              let messageIndex = levels.firstIndex(of: level)
        else {
            return false
        }
        return messageIndex >= currentIndex
    }
}
